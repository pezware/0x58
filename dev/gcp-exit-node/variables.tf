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
