output "project_id" {
  description = "GCP project ID"
  value       = google_project.this.project_id
}

output "zone" {
  description = "VM zone"
  value       = var.zone
}

output "hostname" {
  description = "Tailscale node name of the dev box"
  value       = var.hostname
}

output "backup_bucket" {
  description = "GCS bucket for repo backup snapshots"
  value       = google_storage_bucket.backup.name
}

output "post_apply_steps" {
  description = "Run these after terraform apply"
  value       = <<-EOT

    ── Step 1: add your Tailscale auth key (reusable + pre-authorized) ──
    printf '%s' 'tskey-auth-...' | gcloud secrets versions add exit-dev-tailscale-auth-key \
      --project=${google_project.this.project_id} --data-file=-

    ── Step 2 (optional): add agent API keys for `dev-secrets` to fetch ──
    printf '%s' 'sk-ant-...' | gcloud secrets versions add exit-dev-anthropic-api-key \
      --project=${google_project.this.project_id} --data-file=-
    printf '%s' 'sk-...'     | gcloud secrets versions add exit-dev-openai-api-key \
      --project=${google_project.this.project_id} --data-file=-

    ── Step 3: start the VM (first boot installs the toolchain, ~3-5 min) ──
    ./exit-dev start

    ── Step 4: approve the node in the Tailscale admin console ──
    https://login.tailscale.com/admin/machines

    ── Then: connect over Tailscale ──
    ./exit-dev ssh

  EOT
}
