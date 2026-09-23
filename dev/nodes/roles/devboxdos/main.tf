terraform {
  required_version = ">= 1.10" # use_lockfile — see backend.tf
  required_providers {
    vultr = { source = "vultr/vultr", version = "~> 2.32" }
  }
}

# api_key comes from VULTR_API_KEY in the environment, never from a variable.
#
# Same rule LINODE_TOKEN follows in the Linode roles, and for the same reason: a
# provider credential passed as a Terraform variable reaches tfstate, and this
# state is SHARED between two controllers. ts-node sources it from
# ~/.config/0x58/credentials.env, which is fed from the Mac's Keychain over ssh
# and never enters this repo.
#
# Use the SCOPED sub-user key (`vultr-api-key-devbox`), not the root one. It
# needs `provisioning` and `subscriptions` and nothing else — no billing, no
# manage_users, no root — so a key taken off a compromised controller cannot
# mint further keys or escalate.
provider "vultr" {}

variable "tailscale_auth_key" {
  type      = string
  sensitive = true
}

# The second controller, and the tailnet exit node.
#
# Replaces pezware-cuatro. Do NOT run both: cuatro keeps its own state under
# dev/exit-node/, so this does not adopt it, and leaving it up means paying for
# two exit nodes. Destroy cuatro first.
#
# Worth knowing before you build this at all: devbox already advertises an exit
# node by default, which (per ../../README.md) "makes a standalone exit node
# redundant while devbox is up". So the exit-node duty here is only load-bearing
# in the window where devbox is down — which is exactly the window this box
# exists for, and exactly why it is not simply deleted.
module "node" {
  source = "../../modules/vultr-node"

  label = "pezware-devboxdos"
  role  = "devboxdos"

  # 1 vCPU / 2 GB / 50 GB NVMe, $12/mo. Sized to DRIVE, not to work: terraform,
  # vultr-cli, git and a shell fit comfortably; agents and containers do not.
  # Builds and tests belong on a burst box, which is the whole point.
  #
  # This plan can never be lowered — Vultr upgrades in place and never
  # downgrades — so picking it large "just in case" is a permanent bill.
  plan = "vhp-1c-2gb"

  tailscale_auth_key = var.tailscale_auth_key

  # A dedicated tag, NOT tag:devbox + tag:exit-node together.
  #
  # An auth key grants every tag it carries, so a key wearing both would make
  # this box permanently hold the union of two ACL privilege sets — the thing
  # ../../README.md warns collapses the separation. One tag, one key, and the
  # ACL below grants exactly the two paths this box needs.
  tailscale_tag   = "tag:devboxdos"
  tailscale_flags = "--advertise-exit-node=true"

  # 2 GB is thin for terraform plus a provider plugin. Swap is here so a large
  # plan gets slow instead of OOM-killed; no kubelet runs on this box, so
  # nothing objects to it.
  swap_mb = 2048

  # MUST stay 0 — see the validation in modules/vultr-node/variables.tf.
  # common.sh discovers volumes at a hard-coded Linode device path, so a Vultr
  # volume would attach, bill, and never mount.
  volume_gb = 0

  common_script    = file("${path.module}/../../modules/linode-node/common.sh")
  bootstrap_script = file("${path.module}/bootstrap.sh")
  extra_tags       = ["controller", "exit-node", "permanent"]
}

output "label" { value = module.node.label }
output "instance_id" { value = module.node.instance_id }
output "ipv4" { value = module.node.ipv4 }
output "teardown_check" { value = module.node.teardown_check }

output "post_apply_steps" {
  value = <<-EOT

    ── 1. ACL, in the browser — the node is unreachable until this lands ──
    https://login.tailscale.com/admin/acls/file

      tagOwners:  "tag:devboxdos": ["autogroup:admin"]
                  "tag:burst":     ["autogroup:admin"]

      acls:       my devices  -> tag:devboxdos:*
                  tag:devboxdos -> tag:burst:6443,22
                  tag:burst  -> NOTHING. A burst box runs other people's build
                                code; it gets no path to either controller.

      autoApprovers:  exitNode: ["tag:devboxdos"]
      ssh:            check, autogroup:member -> tag:devboxdos, users arbeitandy+root

    ── 2. hand it the scoped Vultr key (over the tailnet, NOT via user_data) ──
    Deliberately after boot: a value rendered into user_data lands in tfstate
    AND in cloud-init's cache, which is the hazard ../../README.md documents for
    auth keys. This key never goes near either.

      kc() { security find-generic-password -s "$1" -a "$USER" -w; }
      printf 'VULTR_API_KEY=%s\n' "$(kc vultr-api-key-devbox)" \
        | tailscale ssh ${module.node.label} \
            'umask 077; mkdir -p ~/.config/0x58 && cat >> ~/.config/0x58/credentials.env'

    ── 3. allowlist its IP for the Vultr API — console only, no endpoint ──
    /v2/api-keys, /v2/acl and /v2/account/acl all 404. Do it now, not later:
    leave it until devbox is down and the recovery path is what is locked out.

    ── 4. retire the old exit node — or pay for both ──
    cd ../../../exit-node && terraform destroy

  EOT
}
