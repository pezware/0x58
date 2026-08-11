# Remove the default Editor role from the Compute Engine default SA.
# GCP auto-creates it with broad permissions when the compute API is enabled.
resource "google_project_default_service_accounts" "deprivilege" {
  project = google_project.this.project_id
  action  = "DEPRIVILEGE"

  depends_on = [google_project_service.compute]
}

resource "google_service_account" "exit_node" {
  project      = google_project.this.project_id
  account_id   = "tailscale-exit-sa"
  display_name = "Tailscale Exit Node"

  depends_on = [google_project.this]
}

# Only permission: read the tailscale auth key from Secret Manager at startup.
resource "google_project_iam_member" "secret_reader" {
  project = google_project.this.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.exit_node.email}"
}

resource "google_compute_instance" "exit_node" {
  project        = google_project.this.project_id
  name           = "tailscale-exit"
  machine_type   = "e2-micro"
  zone           = var.zone
  can_ip_forward = true # required for GCE to pass transit packets (exit node routing)

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
      type  = "pd-standard"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.exit.id
    # Ephemeral external IP: Tailscale prefers direct paths over relay.
    # IP changes on each start, but that's fine for an exit node.
    access_config {}
  }

  metadata = {
    startup-script         = file("${path.module}/startup.sh")
    enable-oslogin         = "FALSE"
    block-project-ssh-keys = "true"
    serial-port-enable     = "false"
  }

  service_account {
    email  = google_service_account.exit_node.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  # Spot pricing (~70% cheaper than on-demand).
  # STOP on preemption (not DELETE) so Tailscale auth state survives on disk.
  scheduling {
    provisioning_model          = "SPOT"
    preemptible                 = true
    on_host_maintenance         = "TERMINATE"
    automatic_restart           = false
    instance_termination_action = "STOP"
  }

  # Start stopped so the operator can add the Secret Manager auth key before first boot.
  # ignore_changes means terraform apply won't fight with manual ./ts-exit start/stop.
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
  ]
}
