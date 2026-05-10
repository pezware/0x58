# Creates the secret container only — no value is stored here.
# Populate it after apply (see outputs for the command).
# The value never touches git.
resource "google_secret_manager_secret" "tailscale_auth_key" {
  project   = google_project.this.project_id
  secret_id = "tailscale-exit-auth-key"

  replication {
    auto {}
  }

  depends_on = [google_project_service.secretmanager]
}
