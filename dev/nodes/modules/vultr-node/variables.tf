variable "label" {
  description = "Vultr label, hostname, and Tailscale machine name"
  type        = string
}

variable "role" {
  description = "Node role — selects the bootstrap script and is exported to it as ROLE"
  type        = string
}

variable "plan" {
  description = <<-EOT
    Vultr plan ID. The vhp (High Performance) family holds a flat $0.0165/hr per
    vCPU across its whole range, which is why it is the default choice here:

      vhp-1c-2gb     1 vCPU /  2 GB   $0.016/hr   controller floor
      vhp-8c-16gb    8 vCPU / 16 GB   $0.132/hr   burst — kind + tests
      vhp-12c-24gb  12 vCPU / 24 GB   $0.197/hr   burst — wide builds

    Pick the working size at CREATE time. A plan can be raised later but never
    lowered, so a box provisioned large stays expensive until it is destroyed.
  EOT
  type        = string
}

variable "region" {
  description = "Vultr region. ewr = Newark, matching the Linode nodes' us-east."
  type        = string
  default     = "ewr"
}

variable "os_id" {
  description = <<-EOT
    Base image. 2625 = Debian 13 x64 (trixie), the same base linux/setup-guide.md
    targets and the same one modules/linode-node uses, so common.sh needs no
    per-provider branching.
  EOT
  type        = number
  default     = 2625
}

variable "tailscale_auth_key" {
  description = "Pre-authorized auth key. Pulled from Keychain by ts-node, never committed."
  type        = string
  sensitive   = true
}

variable "tailscale_tag" {
  description = "Tailscale ACL tag this node advertises, e.g. tag:k8s. Must exist in tagOwners."
  type        = string
}

variable "tailscale_flags" {
  description = <<-EOT
    Extra flags for `tailscale up`/`set`, space separated. --ssh and
    --accept-dns=false are always applied by common.sh. Add
    --advertise-exit-node here to let a node double as the exit node.
  EOT
  type        = string
  default     = ""
}

variable "common_script" {
  description = <<-EOT
    The shared bootstrap, passed in with file() rather than read from inside this
    module.

    modules/linode-node reads its own copy off disk. This module takes it as an
    input so that both providers can be handed the SAME file without one module
    reaching across into the other's directory, and without a second copy that
    drifts. The role decides where it lives; the module only renders it.
  EOT
  type        = string
}

variable "bootstrap_script" {
  description = "Role-specific bootstrap, sourced after common.sh. Pass with file()."
  type        = string
}

variable "swap_mb" {
  description = <<-EOT
    Swapfile size in MB, 0 to disable.

    Vultr has no equivalent of Linode's separate swap PARTITION, so unlike
    linode-node there is no second knob here and no gap between what the config
    claims and what the node has. Whatever this says is all the swap there is.

    MUST stay 0 on any node running a native kubelet — it refuses to start with
    swap enabled. kind sets failSwapOn: false and tolerates it.
  EOT
  type        = number
  default     = 0

  validation {
    condition     = var.swap_mb >= 0 && floor(var.swap_mb) == var.swap_mb
    error_message = "swap_mb must be a non-negative whole number of megabytes."
  }
}

variable "extra_tags" {
  description = "Additional Vultr instance tags (beyond 0x58 + the role)"
  type        = list(string)
  default     = []
}

variable "volume_gb" {
  description = <<-EOT
    Persistent Block Storage in GB. MUST be 0 today — see the validation below.

    Burst boxes want 0 anyway: they are destroyed after every session and hold
    nothing worth keeping, while a volume carries prevent_destroy and would turn
    each teardown into a two-step manual state edit.
  EOT
  type        = number
  default     = 0

  # Refused rather than allowed-and-broken, because the failure is silent.
  #
  # common.sh discovers the volume at a hard-coded Linode path:
  #
  #   local dev="/dev/disk/by-id/scsi-0Linode_Volume_$${VOLUME_LABEL}"
  #
  # On Vultr that device never appears. common_volume() then waits its full 60
  # seconds and SKIPS the mount, so the node boots healthy, Terraform reports
  # success, the volume is attached and billed, and nothing is mounted at
  # volume_mount. Anything written there lands on the root disk instead and dies
  # with the node -- which is the exact outcome the volume exists to prevent.
  #
  # Lifting this needs common_volume() to learn Vultr's path
  # (/dev/disk/by-id/virtio-* by label) and a real attach test. Until then a
  # loud refusal beats a volume that looks attached and holds nothing.
  validation {
    condition     = var.volume_gb == 0
    error_message = "volume_gb must be 0: common.sh discovers volumes at a hard-coded Linode device path, so a Vultr volume attaches, bills, and never mounts. Teach common_volume() the Vultr path before allowing this."
  }
}

variable "volume_mount" {
  description = "Mount point for the volume inside the node. Mirrors the Mac's ~/src layout."
  type        = string
  default     = "/home/arbeitandy/src"
}
