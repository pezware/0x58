terraform {
  required_version = ">= 1.6"
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Random root password — required by the Linode API but never used.
# Tailscale SSH is the only access path; OpenSSH is disabled in common.sh.
resource "random_password" "root" {
  length  = 32
  special = false
}

resource "linode_instance" "node" {
  label     = var.label
  region    = var.region
  type      = var.type
  image     = var.image
  root_pass = random_password.root.result

  tags = concat(["tailscale", var.role], var.extra_tags)

  metadata {
    # templatefile() cannot see path.module from inside the template, so the
    # scripts are read here and passed as vars — same gotcha documented in
    # dev/exit-node/README.md.
    user_data = base64encode(templatefile("${path.module}/cloud-init.yaml", {
      hostname           = var.label
      tailscale_auth_key = var.tailscale_auth_key
      common_script      = file("${path.module}/common.sh")
      bootstrap_script   = var.bootstrap_script
      # Every value is quoted: this file is `.`-sourced by common.sh, so an
      # unquoted multi-flag string like `--advertise-exit-node --accept-routes`
      # would make the second flag a command and abort the bootstrap before the
      # tailnet join — locking us out of the only access path.
      node_env = join("\n", [
        "ROLE=\"${var.role}\"",
        "TS_TAG=\"${var.tailscale_tag}\"",
        "TS_EXTRA_FLAGS=\"${var.tailscale_flags}\"",
        "SWAP_MB=\"${var.swap_mb}\"",
      ])
    }))
  }

  lifecycle {
    precondition {
      condition     = var.role != "k8s" || var.swap_mb == 0
      error_message = "kubelet refuses to start when swap is enabled, so the k8s role must set swap_mb = 0."
    }
  }
}

# Deny-all inbound. Tailscale needs no open ports — it establishes connectivity
# outbound via DERP/STUN — so the public IP answers nothing at all.
resource "linode_firewall" "node" {
  label = "${var.label}-fw"

  inbound_policy  = "DROP"
  outbound_policy = "ACCEPT"

  linodes = [linode_instance.node.id]
}
