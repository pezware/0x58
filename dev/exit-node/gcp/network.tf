resource "google_compute_network" "main" {
  project                 = google_project.this.project_id
  name                    = "tailscale-net"
  auto_create_subnetworks = false

  depends_on = [google_project_service.compute]
}

resource "google_compute_subnetwork" "exit" {
  project                  = google_project.this.project_id
  name                     = "exit-subnet"
  region                   = local.region
  network                  = google_compute_network.main.id
  ip_cidr_range            = "10.10.0.0/24"
  private_ip_google_access = false
}

# Belt-and-suspenders explicit deny over GCP's implicit deny-all-ingress.
# This makes the intent visible and prevents a future accidental allow-all
# from overriding silently (it would need priority < 1000 to win).
resource "google_compute_firewall" "deny_all_ingress" {
  project   = google_project.this.project_id
  name      = "deny-all-ingress"
  network   = google_compute_network.main.id
  direction = "INGRESS"
  priority  = 1000

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]
}

# Egress: Tailscale connects outbound to its DERP relay network.
# No inbound ports needed — Tailscale punches through NAT outbound-only.
resource "google_compute_firewall" "allow_all_egress" {
  project   = google_project.this.project_id
  name      = "allow-all-egress"
  network   = google_compute_network.main.id
  direction = "EGRESS"
  priority  = 1000

  allow {
    protocol = "all"
  }

  destination_ranges = ["0.0.0.0/0"]
}
