# Facts give each host's architecture, which picks the release tarball.
data "conn3x_host" "facts" {
  for_each = var.hosts

  ssh {
    host             = try(each.value.address, each.value)
    host_key         = try(each.value.host_key, null)
    user             = try(each.value.user, var.ssh_user)
    port             = try(each.value.port, var.ssh_port)
    private_key_file = try(each.value.private_key_file, var.ssh_private_key_file)
    jump_hosts       = try(each.value.jump_hosts, null)
    known_hosts_file = var.ssh_known_hosts_file
  }

  lifecycle {
    postcondition {
      condition     = contains(keys(var.checksums), self.arch)
      error_message = "Host ${each.key} is ${self.arch}. The circuit has runner builds for ${join(" and ", keys(var.checksums))}."
    }
  }
}

locals {
  # GitHub names its runner builds by .NET's architecture names.
  dotnet_arch = { x86_64 = "x64", aarch64 = "arm64" }
  tarball     = { for name, f in data.conn3x_host.facts : name => "actions-runner-linux-${local.dotnet_arch[f.arch]}-${var.runner_version}.tar.gz" }

  token_file = "/etc/github-runner/token"
  unit       = "/etc/systemd/system/github-runner@.service"

  # GitHub's dependency script, used on Debian and Ubuntu, comes in every
  # unpacked runner, so any one of them will do.
  first_runner = sort(keys(var.runners))[0]

  # Each runner gets its own copy of the release: config.sh writes the
  # registration into the directory it runs from.
  dir = { for key in keys(var.runners) : key => "${var.install_dir}/${key}" }

  # The token goes in through the environment, which config.sh reads as
  # ACTIONS_RUNNER_INPUT_TOKEN, so it never shows in the process list.
  config = { for host in keys(var.hosts) : host => { for key, r in var.runners : key => join(" ", compact([
    "cd ${local.dir[key]} &&",
    "ACTIONS_RUNNER_INPUT_TOKEN=\"$(cat ${local.token_file})\" && export ACTIONS_RUNNER_INPUT_TOKEN &&",
    "runuser -u ${var.user} -- ./config.sh --unattended --replace",
    "--url '${var.github_url}'",
    "--name '${coalesce(r.name, "${host}-${key}")}'",
    length(r.labels) == 0 ? "" : "--labels '${join(",", r.labels)}'",
    r.group == null ? "" : "--runnergroup '${r.group}'",
    "--work _work",
    var.auto_update ? "" : "--disableupdate",
  ])) } }

  # The runner replaces its own files when it updates itself, so a runner
  # already at or past runner_version is left alone. The version comes from
  # a file, since the runner itself can't start before its libraries are in.
  current = { for key in keys(var.runners) : key => "v=$(grep -o '\"Runner.Listener/[0-9.]*\"' ${local.dir[key]}/bin/Runner.Listener.deps.json | head -n 1 | cut -d / -f 2 | tr -dc 0-9.) && [ \"$(printf '%s\\n' \"$v\" ${var.runner_version} | sort -V | head -n 1)\" = ${var.runner_version} ]" }

  unit_content = <<-EOT
    # Written by Conn3x. Changes here are overwritten on the next apply.
    [Unit]
    Description=GitHub Actions runner %i
    After=network-online.target
    Wants=network-online.target
    # A runner that isn't registered yet has nothing to run.
    ConditionPathExists=${var.install_dir}/%i/.runner

    [Service]
    User=${var.user}
    Group=${var.user}
    WorkingDirectory=${var.install_dir}/%i
    ExecStart=${var.install_dir}/%i/run.sh
    Restart=on-failure
    RestartSec=10
    # Lets a running job finish its cleanup when the service stops, as the
    # unit svc.sh writes does.
    KillMode=process
    KillSignal=SIGTERM
    TimeoutStopSec=5min

    [Install]
    WantedBy=multi-user.target
  EOT
}

circuit "github_runner" {
  hosts = var.hosts

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  # Minimal images can lack any of these. Jobs need git for actions/checkout
  # to clone rather than download a tarball of the repository.
  step "tools" {
    for_each = toset(["curl", "tar", "gzip", "git"])
    package {
      name = item.value
    }
  }

  step "user" {
    user {
      name   = var.user
      system = true
      home   = "/var/lib/${var.user}"
      shell  = "/bin/bash"
    }
  }

  step "install_dir" {
    directory {
      path = var.install_dir
    }
  }

  step "unit" {
    file {
      path    = local.unit
      content = local.unit_content
    }
  }

  # Picks up a changed unit in runners that are already running.
  step "reload" {
    command {
      command  = "systemctl daemon-reload && systemctl try-restart 'github-runner@*'"
      triggers = { unit = sha256(local.unit_content) }
    }
  }

  step "download" {
    download {
      url    = "https://github.com/actions/runner/releases/download/v${var.runner_version}/${local.tarball[each.key]}"
      sha256 = var.checksums[data.conn3x_host.facts[each.key].arch]
      dest   = "${var.install_dir}/${local.tarball[each.key]}"
    }
  }

  # The runner updates itself in place, so its directory belongs to the
  # runner's user.
  step "runner_dir" {
    for_each = local.dir
    directory {
      path  = item.value
      owner = var.user
      group = var.user
    }
  }

  step "unpack" {
    for_each = local.dir
    command {
      command = "runuser -u ${var.user} -- tar -xzf ${var.install_dir}/${local.tarball[each.key]} -C ${item.value} && systemctl try-restart github-runner@${item.key}"
      unless  = local.current[item.key]
    }
  }

  # The runner needs ICU. On Debian and Ubuntu, GitHub's own script finds
  # the package under its versioned name, such as libicu74. On the Red Hat
  # family the script also wants lttng-ust, which Rocky Linux only has in
  # EPEL and the runner can do without, so the circuit installs libicu alone.
  # The check looks for ICU rather than starting the runner, which would
  # leave root-owned logs in its directory.
  step "dependencies" {
    command {
      command = data.conn3x_host.facts[each.key].os_family == "debian" ? "${local.dir[local.first_runner]}/bin/installdependencies.sh" : "dnf -y install libicu"
      unless  = "ldconfig -p | grep -q libicuuc"
    }
  }

  step "token_dir" {
    for_each = var.register ? toset(["token"]) : toset([])
    directory {
      path = dirname(local.token_file)
      mode = "0700"
    }
  }

  step "token" {
    for_each = var.register ? toset(["token"]) : toset([])
    file {
      path       = local.token_file
      content_wo = var.registration_token
      # Setting register = false removes the step, and with it the token.
      on_remove = "delete"
    }
  }

  # Registers each runner once. .runner appears when config.sh succeeds.
  step "config" {
    for_each = var.register ? local.dir : {}
    command {
      command = local.config[each.key][item.key]
      creates = "${item.value}/.runner"
    }
  }

  # With register = false the circuit doesn't start runners, since one that
  # was never registered can't run. It still enables them, and systemd
  # skips any without a registration at boot.
  step "service" {
    for_each = local.dir
    service {
      name    = "github-runner@${item.key}"
      state   = var.register ? "started" : null
      enabled = true
      # Removing a runner, or the module, stops it. It stays registered with
      # GitHub until you remove it there.
      on_remove = "delete"
    }
  }
}
