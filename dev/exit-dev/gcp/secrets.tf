# Secret containers only — no values are stored here. Populate them after
# apply (see outputs). Values never touch git or the VM disk: the startup
# script and the `dev-secrets` helper fetch them at runtime via the
# instance service-account token.

resource "google_secret_manager_secret" "tailscale_auth_key" {
  project   = google_project.this.project_id
  secret_id = "exit-dev-tailscale-auth-key"

  replication {
    auto {}
  }

  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret" "anthropic_api_key" {
  project   = google_project.this.project_id
  secret_id = "exit-dev-anthropic-api-key"

  replication {
    auto {}
  }

  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret" "openai_api_key" {
  project   = google_project.this.project_id
  secret_id = "exit-dev-openai-api-key"

  replication {
    auto {}
  }

  depends_on = [google_project_service.secretmanager]
}

# Optional fallback for git auth. Prefer `gh auth login` (device flow) — a
# short-lived, revocable session beats a long-lived token on the box.
resource "google_secret_manager_secret" "git_token" {
  project   = google_project.this.project_id
  secret_id = "exit-dev-git-token"

  replication {
    auto {}
  }

  depends_on = [google_project_service.secretmanager]
}
