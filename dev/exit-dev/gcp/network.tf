resource "google_compute_network" "main" {
  project                 = google_project.this.project_id
  name                    = "dev-net"
  auto_create_subnetworks = false

  depends_on = [google_project_service.compute]
}

resource "google_compute_subnetwork" "dev" {
  project                  = google_project.this.project_id
  name                     = "dev-subnet"
  region                   = local.region
  network                  = google_compute_network.main.id
  ip_cidr_range            = "10.20.0.0/24"
  private_ip_google_access = false
}

# Belt-and-suspenders explicit deny over GCP's implicit deny-all-ingress.
# Access is Tailscale SSH only — no inbound ports are ever needed.
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

# Egress: Tailscale connects outbound to its DERP relays; the box also pulls
# packages, container images and Go modules. NAT punching is outbound-only.
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
