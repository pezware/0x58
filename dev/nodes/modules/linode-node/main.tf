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

  # A resize is a migration to a different physical host, and the disks are
  # copied at ~150 MB/sec -- about 9 minutes for the devbox's 79.5 GB root. The
  # provider defaults this to "cold", which powers the instance down for that
  # entire window. Warm keeps it up during the copy and only reboots at the end.
  #
  # Warm is not free of downtime and it is not infallible: Linode reboots the
  # instance once the migration completes, and a warm resize that cannot power
  # the instance down FAILS rather than falling back -- retry it as a cold one.
  migration_type = var.migration_type

  # NEVER set this true. It is the one-way door in this whole design.
  #
  # Linode grows disks but does not shrink them: Cloud Manager only offers Auto
  # Resize Disk when "the new plan provides more storage space than the current
  # plan", and the provider is blunt about it -- "This is an irreversible action
  # as Linode disks cannot be automatically downsized."
  #
  # So accepting it once on the way up to g6-standard-4 would grow the root disk
  # from 79.5 GB to 160 GB, and g6-standard-2 (80 GB of storage) would become
  # unreachable without a manual resize2fs. Pinned false rather than exposed as
  # a variable, because the failure is silent at the moment you opt in and only
  # surfaces months later when you try to scale back down.
  #
  # The devbox has exactly the layout that makes Linode offer the checkbox --
  # one ext4 disk plus a swap disk -- so this is a live footgun, not a
  # theoretical one. Keeping the disk fixed is what makes resizing REVERSIBLE.
  resize_disk = false

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
    # user_data is a FIRST-BOOT input, and the Linode API offers no way to update
    # it on a live instance. So when the bootstrap scripts move on in git,
    # Terraform's only available remedy is to replace the node -- and it proposes
    # that for any apply, however unrelated. On the devbox that means losing 32 GB
    # of container storage, a kind cluster and six manual recovery steps because a
    # comment block changed.
    #
    # Silencing an ACTIONABLE diff would be wrong. This one is not actionable: the
    # sole fix Terraform has is disproportionate to every cause. So the diff is
    # ignored here and conformance moves to where it can actually be repaired --
    # `devbox-drift` compares the installed scripts against the repo byte for byte
    # (verified lossless: /usr/local/sbin/node-common.sh is identical to
    # common.sh), and `ts-node <role> sync-bootstrap` reinstalls them in seconds.
    #
    # Consequences, both deliberate:
    #   - A rebuild is now an explicit act: terraform apply -replace=...
    #     Which is where that decision belongs, not a side effect of an apply.
    #   - A re-minted Tailscale auth key no longer forces replacement either.
    #     Desirable -- rotating a key should not destroy the node -- but it does
    #     mean the key in state can go stale relative to the Keychain.
    #
    # Not conditional per role, because Terraform forbids variables in lifecycle.
    # For k8s that is nearly free: it is cattle, destroyed after every session, so
    # the next apply builds fresh with current user_data anyway.
    ignore_changes = [metadata]

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
