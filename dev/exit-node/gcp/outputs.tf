output "project_id" {
  description = "GCP project ID"
  value       = google_project.this.project_id
}

output "zone" {
  description = "VM zone"
  value       = var.zone
}

output "post_apply_steps" {
  description = "Run these after terraform apply"
  value       = <<-EOT

    ── Step 1: add your Tailscale auth key (reusable + pre-authorized) ──
    printf '%s' 'tskey-auth-...' | gcloud secrets versions add tailscale-exit-auth-key \
      --project=${google_project.this.project_id} --data-file=-

    ── Step 2: approve the exit node in the Tailscale admin console ──
    https://login.tailscale.com/admin/machines
    (or pre-approve via ACL tag — see Tailscale docs)

    ── Step 3: start the VM ──
    ./ts-exit start

    ── Then: use Tailscale to SSH in ──
    ./ts-exit ssh

  EOT
}
