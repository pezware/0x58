terraform {
  required_version = ">= 1.6"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "google" {}

locals {
  # Strip the trailing zone letter: us-east1-b → us-east1, europe-west4-a → europe-west4
  region = join("-", slice(split("-", var.zone), 0, length(split("-", var.zone)) - 1))
}

resource "random_id" "suffix" {
  byte_length = 3
}

resource "google_project" "this" {
  name                = "Tailscale Exit Node"
  project_id          = "ts-exit-${random_id.suffix.hex}"
  billing_account     = var.billing_account
  auto_create_network = false # prevents the insecure default VPC from being created
}

# Only the two APIs this project actually uses. Nothing else is enabled.
resource "google_project_service" "compute" {
  project            = google_project.this.project_id
  service            = "compute.googleapis.com"
  disable_on_destroy = false

  depends_on = [google_project.this]

  timeouts {
    create = "10m"
  }
}

resource "google_project_service" "secretmanager" {
  project            = google_project.this.project_id
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false

  depends_on = [google_project.this]

  timeouts {
    create = "10m"
  }
}
