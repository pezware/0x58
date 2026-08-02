terraform {
  required_version = ">= 1.6"
  required_providers {
    linode = { source = "linode/linode", version = "~> 2.0" }
    random = { source = "hashicorp/random", version = "~> 3.0" }
  }
}

# Token from LINODE_TOKEN env, set by ts-node from Keychain. Never a variable,
# so it cannot land in tfstate or a tfvars file.
provider "linode" {}

variable "tailscale_auth_key" {
  type      = string
  sensitive = true
}

variable "advertise_exit_node" {
  description = <<-EOT
    Let the devbox also serve as the tailnet exit node, making the standalone
    Nanode redundant. Set false to keep the roles separate — e.g. when scaling
    back down to `minimal` only.
  EOT
  type        = bool
  default     = true
}

module "node" {
  source = "../../modules/linode-node"

  label = "pezware-devbox"
  role  = "devbox"

  # g6-standard-2: 2 vCPU / 4 GB / 80 GB / $24 mo. Always on — this is the box
  # that holds repos and keeps Claude Code and Codex alive in tmux.
  #
  # 4 GB, not 2: Anthropic documents 4 GB as Claude Code's minimum, and the 2 GB
  # build left roughly 600 MB of headroom with a single agent idle. Changing
  # `type` is an in-place Linode resize (with a reboot), not a rebuild.
  type = "g6-standard-2"

  tailscale_auth_key = var.tailscale_auth_key
  tailscale_tag      = "tag:devbox"
  # Explicit =true/=false rather than present/absent: `tailscale set` only
  # changes settings you actually pass, so omitting the flag would leave a
  # previously-advertised exit node still advertising.
  tailscale_flags = var.advertise_exit_node ? "--advertise-exit-node=true" : "--advertise-exit-node=false"

  # Kept at 4 GB even after the RAM upgrade: golangci-lint and Go builds still
  # spike well past resident memory, and swap is safe here precisely because
  # this node never runs kubelet.
  swap_mb = 4096

  # 50 GB at $0.10/GB = $5/mo, mounted at ~/src to mirror the Mac's layout.
  # Measured payload for the iden2 tree is ~10.4 GB once node_modules and
  # .terraform are excluded — both fully reproducible from lockfiles — so 50 GB
  # leaves substantial room for additional worktrees.
  volume_gb    = 50
  volume_mount = "/home/arbeitandy/src"

  bootstrap_script = file("${path.module}/bootstrap.sh")
  extra_tags       = ["always-on"]
}

output "label" { value = module.node.label }
output "instance_id" { value = module.node.instance_id }
output "ipv4" { value = module.node.ipv4 }

output "post_apply_steps" {
  value = <<-EOT

    ── connect ──
    ./ts-node devbox ssh
    tmux new -s main        # then run claude / codex inside it

    ── from phone or tablet ──
    mosh ${module.node.label} -- tmux attach -t main

    ── if the full restore did not finish (check /var/log/cloud-init-output.log) ──
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/pezware/0x58/main/linux/start.sh)"

  EOT
}
