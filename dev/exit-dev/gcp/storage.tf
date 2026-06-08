# Backup bucket — disaster-recovery snapshots of the repos only. The data
# disk is the primary store; this bucket covers disk loss or a full teardown.
resource "google_storage_bucket" "backup" {
  project                     = google_project.this.project_id
  name                        = "exit-dev-backup-${random_id.suffix.hex}"
  location                    = local.region
  force_destroy               = true
  uniform_bucket_level_access = true

  # Snapshots are rsync'd in place; expire stale objects to cap storage cost.
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_project_service.storage]
}

resource "google_storage_bucket_iam_member" "backup_writer" {
  bucket = google_storage_bucket.backup.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.dev.email}"
}
