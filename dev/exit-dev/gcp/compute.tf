# Remove the default Editor role from the Compute Engine default SA.
# GCP auto-creates it with broad permissions when the compute API is enabled.
resource "google_project_default_service_accounts" "deprivilege" {
  project = google_project.this.project_id
  action  = "DEPRIVILEGE"

  depends_on = [google_project_service.compute]
}

resource "google_service_account" "dev" {
  project      = google_project.this.project_id
  account_id   = "exit-dev-sa"
  display_name = "Remote Dev Box"

  depends_on = [google_project.this]
}

# Read secrets (Tailscale auth key, agent API keys) from Secret Manager.
resource "google_project_iam_member" "secret_reader" {
  project = google_project.this.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.dev.email}"
}

# Persistent data disk — its own resource so it survives VM rebuilds
# (machine-type changes, image upgrades). Holds /var/lib/docker and the
# dev user's home (repos). A spot preemption only STOPs the VM, so this
# disk — and the boot disk — persist across the normal start/stop cycle.
resource "google_compute_disk" "data" {
  project = google_project.this.project_id
  name    = "exit-dev-data"
  type    = "pd-balanced"
  zone    = var.zone
  size    = var.data_disk_size

  depends_on = [google_project_service.compute]
}

resource "google_compute_instance" "dev" {
  project      = google_project.this.project_id
  name         = "exit-dev"
  machine_type = var.machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = var.boot_disk_size
      type  = "pd-balanced"
    }
  }

  attached_disk {
    source      = google_compute_disk.data.id
    device_name = "exit-dev-data" # → /dev/disk/by-id/google-exit-dev-data
  }

  network_interface {
    subnetwork = google_compute_subnetwork.dev.id
    # Ephemeral external IP for outbound pulls; Tailscale prefers direct paths.
    access_config {}
  }

  metadata = {
    startup-script         = file("${path.module}/startup.sh")
    enable-oslogin         = "FALSE"
    block-project-ssh-keys = "true"
    serial-port-enable     = "false"
    dev-hostname           = var.hostname
    github-user            = var.github_user
    backup-bucket          = google_storage_bucket.backup.name
    backup-src             = var.backup_src
  }

  service_account {
    email  = google_service_account.dev.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  # Spot pricing (~70% cheaper than on-demand).
  # STOP on preemption (not DELETE) so both disks survive — repos and the
  # agent's checkpointed work persist across a preemption.
  scheduling {
    provisioning_model          = "SPOT"
    preemptible                 = true
    on_host_maintenance         = "TERMINATE"
    automatic_restart           = false
    instance_termination_action = "STOP"
  }

  # Start stopped so the operator can add the Secret Manager auth key first.
  # ignore_changes means terraform apply won't fight ./exit-dev start/stop.
  desired_status            = "TERMINATED"
  allow_stopping_for_update = true

  lifecycle {
    ignore_changes = [desired_status]
  }

  depends_on = [
    google_project_service.compute,
    google_compute_firewall.deny_all_ingress,
    google_project_iam_member.secret_reader,
    google_project_default_service_accounts.deprivilege,
    google_compute_disk.data,
    google_storage_bucket.backup,
  ]
}
