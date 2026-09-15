terraform {
  required_version = ">= 1.10" # use_lockfile on the S3 backend needs 1.10+
  required_providers {
    vultr = {
      source  = "vultr/vultr"
      version = "~> 2.32"
    }
  }
}

# The Vultr sibling of modules/linode-node. Same contract, same common.sh, same
# cloud-init shape -- the differences below are all forced by the provider, and
# each one is noted where it bites.
#
# Why a second module rather than a provider variable in the first: Terraform
# resource types are not parameterisable. `linode_instance` and `vultr_instance`
# are different types with different attribute names, so one module cannot cover
# both without a count/for_each pair that doubles every line and halves the
# readability. Two small modules with one shared bootstrap is the cheaper shape.

resource "vultr_instance" "node" {
  region = var.region
  plan   = var.plan
  os_id  = var.os_id

  label    = var.label
  hostname = var.label

  # THE ONE-WAY DOOR, and the reason this module has no resize path.
  #
  # Vultr upgrades a plan in place and NEVER downgrades it. The provider does not
  # know that: only `hostname` is ForceNew here, so `plan` is an in-place update
  # and `terraform plan` will happily show a shrink. The Vultr API then refuses it
  # at APPLY, which is the worst place for that failure to land.
  #
  # So the burst box is created at its full working size and destroyed at the end,
  # rather than parked small and scaled up. That is not a workaround -- it is
  # strictly cheaper than the Linode floor-and-resize loop it replaces, which
  # costs a host migration each way plus a reboot that brings no containers back.
  #
  # If you are tempted to add a `resize` command here: it can only ever go up.

  # PLAIN TEXT, not base64, and NOT base64gzip.
  #
  # The provider base64-encodes this itself --
  # resource_vultr_instance.go:355 does base64.StdEncoding.EncodeToString on
  # whatever string it is given. Passing base64gzip() the way linode-node does
  # would hand the guest base64-of-gzip after the provider's own decode, and
  # cloud-init would see printable ASCII instead of gzip magic bytes, skip the
  # decompress, and fail to parse the config. The node would then boot clean,
  # join nothing, and be unreachable -- with no error anywhere that names the
  # encoding.
  #
  # The cost of plain text is size. Linode caps user_data at 16 KB DECODED and
  # the k8s role already crossed it at 17.2 KB, which is why that module gzips.
  # Vultr's limit is NOT verified here. If a large role fails at create with a
  # 4xx naming user_data, that is this line, and the fix is to shrink the
  # bootstrap rather than to reach for gzip.
  user_data = templatefile("${path.module}/cloud-init.yaml", {
    hostname           = var.label
    tailscale_auth_key = var.tailscale_auth_key
    common_script      = var.common_script
    bootstrap_script   = var.bootstrap_script

    # Every value is quoted: this file is `.`-sourced by common.sh, so an
    # unquoted multi-flag string like `--advertise-exit-node --accept-routes`
    # would make the second flag a command and abort the bootstrap before the
    # tailnet join -- locking us out of the only access path.
    node_env = join("\n", [
      "ROLE=\"${var.role}\"",
      "TS_TAG=\"${var.tailscale_tag}\"",
      "TS_EXTRA_FLAGS=\"${var.tailscale_flags}\"",
      "SWAP_MB=\"${var.swap_mb}\"",
      "VOLUME_LABEL=\"${var.volume_gb > 0 ? "${var.label}-data" : ""}\"",
      "VOLUME_MOUNT=\"${var.volume_mount}\"",
    ])
  })

  # Tags are how ts-node finds a node, because a LABEL CANNOT IDENTIFY ONE.
  #
  # Measured 2026-09-15: Vultr accepted two instances carrying an identical
  # label, both HTTP 202. Linode refuses that, and roles/testbox leans on the
  # refusal -- "a second apply against a live node is refused by the API rather
  # than by anyone remembering the rule". No such refusal exists here.
  #
  # Tags do not fix it either: two callers can both list, both see nothing, and
  # both create. Only the state lock makes a singleton real, which is why this
  # module requires a backend with locking and why ts-node must never run it
  # against local state.
  tags = concat(["0x58", var.role], var.extra_tags)

  backups          = "disabled"
  activation_email = false
  enable_ipv6      = true

  firewall_group_id = vultr_firewall_group.node.id

  lifecycle {
    # Same reasoning as linode-node's `ignore_changes = [metadata]`, one field
    # over. user_data is a FIRST-BOOT input and the API cannot update it on a
    # live instance, so Terraform's only remedy for a drifted bootstrap is to
    # REPLACE the node -- and it proposes that for any apply, however unrelated.
    #
    # Silencing an actionable diff would be wrong. This one is not actionable:
    # the sole fix is disproportionate to every cause. Conformance moves to
    # `ts-node <role> sync-bootstrap`, which reinstalls the scripts in seconds.
    #
    # A rebuild therefore becomes an explicit act:
    #   terraform apply -replace='module.node.vultr_instance.node'
    ignore_changes = [user_data]

    precondition {
      condition     = var.role != "k8s" || var.swap_mb == 0
      error_message = "kubelet refuses to start when swap is enabled, so the k8s role must set swap_mb = 0."
    }
  }
}

# Deny-all inbound. Tailscale needs no open ports -- it establishes connectivity
# outbound via DERP/STUN -- so the public IP answers nothing at all.
#
# A Vultr firewall group with NO rules drops everything inbound, which is the
# posture linode_firewall gets from `inbound_policy = "DROP"`. The emptiness IS
# the policy, so there is deliberately no vultr_firewall_rule below. Adding one
# "just for SSH" would undo the entire access model: OpenSSH is disabled by
# common.sh and Tailscale SSH is the only path in.
resource "vultr_firewall_group" "node" {
  description = "${var.label} — deny all inbound"
}

# Persistent working storage, attached at boot and mounted by common_volume().
#
# prevent_destroy is deliberate: this holds working trees, so `terraform destroy`
# MUST fail loudly rather than quietly deleting them. To tear the whole thing
# down on purpose, drop it from state first:
#
#   terraform -chdir=roles/<role> state rm 'module.node.vultr_block_storage.data[0]'
#
# which orphans the volume intact (still billed) and lets the node destroy.
#
# Burst boxes set volume_gb = 0. Nothing on them is worth keeping, and a volume
# would turn every teardown into a two-step manual state edit.
resource "vultr_block_storage" "data" {
  count = var.volume_gb > 0 ? 1 : 0

  region               = var.region
  size_gb              = var.volume_gb
  label                = "${var.label}-data"
  attached_to_instance = vultr_instance.node.id

  lifecycle {
    prevent_destroy = true
  }
}
