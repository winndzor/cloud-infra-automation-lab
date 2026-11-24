output "name" {
  description = "Bucket name."
  value       = google_storage_bucket.this.name
}

output "safety_controls" {
  description = "Safety controls enforced by this module."
  value = {
    force_destroy                 = google_storage_bucket.this.force_destroy
    public_access_prevention      = google_storage_bucket.this.public_access_prevention
    uniform_bucket_level_access   = google_storage_bucket.this.uniform_bucket_level_access
    versioning_enabled            = google_storage_bucket.this.versioning[0].enabled
    soft_delete_retention_seconds = google_storage_bucket.this.soft_delete_policy[0].retention_duration_seconds
    current_object_retention_days = var.current_object_retention_days
  }
}
