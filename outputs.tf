output "runner_names" {
  description = "Name each runner registers with, by host and runner key."
  value       = { for host in keys(var.hosts) : host => { for key, r in var.runners : key => coalesce(r.name, "${host}-${key}") } }
}

output "services" {
  description = "systemd unit of each runner, by runner key. They're the same on every host."
  value       = { for key in keys(var.runners) : key => "github-runner@${key}.service" }
}
