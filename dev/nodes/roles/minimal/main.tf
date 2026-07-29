terraform {
  required_version = ">= 1.6"
  required_providers {
    linode = { source = "linode/linode", version = "~> 2.0" }
    random = { source = "hashicorp/random", version = "~> 3.0" }
  }
}

provider "linode" {}

variable "tailscale_auth_key" {
  type      = string
  sensitive = true
}

# The fall-back tier: when devbox and k8s are destroyed, this is the one box
# that stays, keeping the tailnet exit node alive for ~$5/mo.
#
# Reuses tag:exit-node and the existing 'tailscale-exit-authkey' Keychain item,
# so no new Tailscale setup is needed. It does NOT adopt the running
# pezware-cuatro — that instance keeps its own state under dev/exit-node/.
# Destroy that one first if you build this, or you will pay for both.
module "node" {
  source = "../../modules/linode-node"

  label = "pezware-minimal"
  role  = "minimal"
  type  = "g6-nanode-1" # 1 vCPU / 1 GB / 25 GB / $5 mo

  tailscale_auth_key = var.tailscale_auth_key
  tailscale_tag      = "tag:exit-node"
  tailscale_flags    = "--advertise-exit-node"

  swap_mb = 0

  bootstrap_script = file("${path.module}/bootstrap.sh")
  extra_tags       = ["exit-node"]
}

output "label" { value = module.node.label }
output "instance_id" { value = module.node.instance_id }
output "ipv4" { value = module.node.ipv4 }

output "post_apply_steps" {
  value = <<-EOT

    Exit-node advertisement is auto-approved by the autoApprovers ACL rule
    (see dev/exit-node/README.md). Select ${module.node.label} as your exit
    node in the Tailscale client.

  EOT
}
