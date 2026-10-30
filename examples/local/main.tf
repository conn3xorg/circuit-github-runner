variable "port" {
  type    = number
  default = 2309
}

# The repository to register with. Use a private one: see the README's
# security notes.
variable "github_url" {
  type    = string
  default = "https://github.com/OWNER/REPO"
}

# Leave register false to install the runner without registering it. To
# register, pass -var register=true and the token in
# TF_VAR_registration_token.
variable "register" {
  type    = bool
  default = false
}

variable "registration_token" {
  type      = string
  default   = null
  ephemeral = true
  sensitive = true
}

module "github_runner" {
  source = "../.."

  hosts                = { box = "127.0.0.1" }
  ssh_port             = var.port
  ssh_private_key_file = "./id_ed25519"
  ssh_known_hosts_file = "./known_hosts"

  github_url         = var.github_url
  register           = var.register
  registration_token = var.registration_token

  runners = {
    build = { labels = ["conn3x-test"] }
  }
}
