variable "region" {
  description = "Linode region (us-east = Newark; closest match to GCP us-east1-b for East Coast latency)"
  type        = string
  default     = "us-east"
}

variable "type" {
  description = "Nanode 1GB — 1 vCPU shared, 1 GiB RAM, 25 GB SSD, 1 TB transfer. $5/mo flat (no spot tier)."
  type        = string
  default     = "g6-nanode-1"
}

variable "label" {
  description = "Linode label and Tailscale hostname"
  type        = string
  default     = "pezware-cuatro"
}

variable "tailscale_auth_key" {
  description = "Tailscale auth key (reusable + pre-authorized). Pulled from macOS Keychain by ts-exit, never committed."
  type        = string
  sensitive   = true
}
