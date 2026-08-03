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
  swap_size = var.linode_swap_mb

  tags = concat(["tailscale", var.role], var.extra_tags)

  metadata {
    # templatefile() cannot see path.module from inside the template, so the
    # scripts are read here and passed as vars — same gotcha documented in
    # dev/exit-node/README.md.
    # base64gzip, not base64encode. Linode caps user_data at 16 KB DECODED, and
    # the embedded common.sh plus a role bootstrap crossed it: the k8s role failed
    # outright at 17.2 KB, and devbox sat 66 bytes under the limit -- one more
    # comment line from breaking its rebuild silently.
    #
    # cloud-init detects gzip by magic bytes and decompresses, so the decoded
    # payload Linode measures is the compressed one: ~6.6 KB instead of ~17 KB.
    # The alternatives were worse. Stripping comments destroys the reasoning
    # these scripts exist to carry, and fetching them at boot adds a network
    # dependency to the one path that has to work when things are already broken.
    user_data = base64gzip(templatefile("${path.module}/cloud-init.yaml", {
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
        "VOLUME_LABEL=\"${var.volume_gb > 0 ? "${var.label}-data" : ""}\"",
        "VOLUME_MOUNT=\"${var.volume_mount}\"",
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

# Persistent working storage, attached at boot and mounted by common_volume().
#
# prevent_destroy is deliberate: this holds working trees, so `terraform destroy`
# MUST fail loudly rather than quietly deleting them. To tear the whole thing
# down on purpose, drop it from state first:
#
#   terraform -chdir=roles/devbox state rm 'module.node.linode_volume.data[0]'
#
# which orphans the volume intact (still billed) and lets the node destroy.
resource "linode_volume" "data" {
  count = var.volume_gb > 0 ? 1 : 0

  label     = "${var.label}-data"
  region    = var.region
  size      = var.volume_gb
  linode_id = linode_instance.node.id

  tags = ["0x58", var.role]

  lifecycle {
    prevent_destroy = true
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
