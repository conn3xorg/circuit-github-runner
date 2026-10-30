variable "hosts" {
  type        = any
  description = "Hosts to configure: a map of names to addresses, or to host objects with an address and optional host_key, user, port, private_key_file or jump_hosts."
}

variable "ssh_user" {
  type        = string
  default     = "root"
  description = "User to log in as."
}

variable "ssh_port" {
  type        = number
  default     = 22
  description = "SSH port."
}

variable "ssh_private_key_file" {
  type        = string
  default     = null
  description = "Path to a private key. When null, Conn3x uses the SSH agent."
}

variable "ssh_known_hosts_file" {
  type        = string
  default     = null
  description = "known_hosts file to check host keys against. When null, ~/.ssh/known_hosts."
}

variable "ssh_become" {
  type        = bool
  default     = false
  description = "Run commands as root through sudo."
}


variable "github_url" {
  type        = string
  description = "Repository, organization or enterprise the runners register with, such as \"https://github.com/acme/app\" or \"https://github.com/acme\"."

  validation {
    condition     = can(regex("^https://[^\\s'\"]+[^/]$", var.github_url))
    error_message = "github_url must be an https URL without a trailing slash, such as \"https://github.com/acme/app\"."
  }
}

variable "register" {
  type        = bool
  default     = true
  description = "Register runners that aren't registered yet, with registration_token. Set it to false once they are, so later plans don't need a token."
}

variable "registration_token" {
  type        = string
  default     = null
  ephemeral   = true
  sensitive   = true
  description = "Registration token from GitHub's \"New self-hosted runner\" page or its API. It expires after an hour. Required when register is true."

  validation {
    condition     = !var.register || (var.registration_token != null && var.registration_token != "")
    error_message = "Set registration_token, or set register = false once the runners are registered."
  }
}

variable "runners" {
  type = map(object({
    name   = optional(string)
    labels = optional(list(string), [])
    group  = optional(string)
  }))
  default     = { runner = {} }
  description = "Runners to run on each host, by key. name defaults to HOST-KEY, labels are added to self-hosted, Linux and X64 or ARM64, and group is an organization's runner group."

  validation {
    condition     = length(var.runners) > 0
    error_message = "runners needs at least one runner."
  }

  validation {
    condition     = alltrue([for key in keys(var.runners) : can(regex("^[a-zA-Z0-9][a-zA-Z0-9_.-]*$", key))])
    error_message = "Runner keys may use letters, digits, ., - and _, since each names a directory and a systemd unit."
  }

  validation {
    condition = alltrue(flatten([for r in values(var.runners) : [
      for v in concat([coalesce(r.name, "x"), coalesce(r.group, "x")], r.labels) : can(regex("^[a-zA-Z0-9][a-zA-Z0-9 _.-]*$", v))
    ]]))
    error_message = "A runner's name, labels and group may use letters, digits, spaces, ., - and _. A label can't contain a comma."
  }
}

variable "runner_version" {
  type        = string
  default     = "2.338.2"
  description = "actions/runner release to install, without the leading v."

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.runner_version))
    error_message = "runner_version is a version such as \"2.338.2\", without the leading v."
  }
}

variable "checksums" {
  type        = map(string)
  description = "SHA-256 of the release tarball for each architecture, x86_64 and aarch64, from the release notes. Change these with runner_version."
  default = {
    x86_64  = "baebf204307bac6193480852732f0aba2ae97b6c5597c244f4d5558390147c40"
    aarch64 = "670adb2f268fe21dcbb58b3db0e0aa9d5b3bddfe2c651481336e561ff86de945"
  }

  validation {
    condition     = alltrue([for a, c in var.checksums : contains(["x86_64", "aarch64"], a) && can(regex("^[0-9a-f]{64}$", c))])
    error_message = "checksums maps x86_64 or aarch64 to a SHA-256 in lowercase hex."
  }
}

variable "auto_update" {
  type        = bool
  default     = true
  description = "Let each runner update itself when GitHub releases a new version. When false, update by raising runner_version, and do it within 30 days of each release or GitHub stops sending jobs."
}

variable "user" {
  type        = string
  default     = "github-runner"
  description = "System user the runners and their jobs run as. The circuit creates it, without sudo."

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_-]*$", var.user)) && var.user != "root"
    error_message = "user must be a valid user name, and not root."
  }
}

variable "install_dir" {
  type        = string
  default     = "/opt/actions-runner"
  description = "Directory that holds the tarball and one directory per runner."

  validation {
    condition     = can(regex("^/[a-zA-Z0-9/_.-]*[^/]$", var.install_dir))
    error_message = "install_dir must be an absolute path without a trailing slash."
  }
}
