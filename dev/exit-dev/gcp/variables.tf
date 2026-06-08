variable "billing_account" {
  description = "GCP billing account ID"
  type        = string
  default     = "0157E6-670C66-73750B"
}

variable "zone" {
  description = "GCP zone for the VM — region is derived automatically (e.g. us-east1-b → us-east1)"
  type        = string
  default     = "us-east1-b"
}

variable "machine_type" {
  description = "VM machine type — sized for a heavy kind cluster (Istio + Gateway API) plus Go builds and an agent"
  type        = string
  default     = "e2-standard-8"
}

variable "boot_disk_size" {
  description = "Boot disk size in GB (OS only — image cache and repos live on the data disk)"
  type        = number
  default     = 30
}

variable "data_disk_size" {
  description = "Persistent data disk size in GB (repos + Docker image cache). Survives VM rebuilds."
  type        = number
  default     = 80
}

variable "github_user" {
  description = "GitHub username whose public keys seed the dev user's authorized_keys"
  type        = string
  default     = "arbeitandy"
}

variable "hostname" {
  description = "Tailscale node name and OS hostname for the dev box"
  type        = string
  default     = "pezware-dev"
}

variable "backup_src" {
  description = "Home-relative dir rsync'd to the GCS backup bucket daily (\"src\" covers ~/src/iden2 and ~/src/public)"
  type        = string
  default     = "src"
}
