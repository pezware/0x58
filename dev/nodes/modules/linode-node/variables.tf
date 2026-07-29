variable "label" {
  description = "Linode label, hostname, and Tailscale machine name"
  type        = string
}

variable "role" {
  description = "Node role — selects the bootstrap script and is exported to it as ROLE"
  type        = string
}

variable "type" {
  description = "Linode plan. g6-nanode-1 (1GB/$5), g6-standard-1 (2GB/$12), g6-standard-2 (4GB/$24)"
  type        = string
}

variable "region" {
  description = "Linode region (us-east = Newark, matching the existing exit node)"
  type        = string
  default     = "us-east"
}

variable "image" {
  description = "Base image. Debian 13 = trixie, matching linux/setup-guide.md."
  type        = string
  default     = "linode/debian13"
}

variable "tailscale_auth_key" {
  description = "Reusable + pre-authorized auth key. Pulled from Keychain by ts-node, never committed."
  type        = string
  sensitive   = true
}

variable "tailscale_tag" {
  description = "Tailscale ACL tag this node advertises, e.g. tag:devbox. Must exist in tagOwners."
  type        = string
}

variable "tailscale_flags" {
  description = <<-EOT
    Extra flags for `tailscale up`/`set`, space separated. --ssh and --accept-dns=false
    are always applied. Add --advertise-exit-node here to let a node double as the exit
    node, which is how devbox replaces the standalone Nanode.
  EOT
  type        = string
  default     = ""
}

variable "bootstrap_script" {
  description = "Role-specific bootstrap, sourced after common.sh. Pass with file()."
  type        = string
}

variable "swap_mb" {
  description = <<-EOT
    Swapfile size in MB, 0 to disable. Non-zero on the devbox to stretch 2 GB;
    MUST stay 0 on any k8s node — kubelet refuses to start with swap enabled.
  EOT
  type        = number
  default     = 0
}

variable "extra_tags" {
  description = "Additional Linode instance tags (beyond tailscale + the role)"
  type        = list(string)
  default     = []
}
