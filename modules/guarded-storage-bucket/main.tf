resource "google_storage_bucket" "this" {
  project  = var.project_id
  name     = var.name
  location = var.location

  force_destroy               = false
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  labels                      = var.labels

  versioning {
    enabled = true
  }

  soft_delete_policy {
    retention_duration_seconds = 604800
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }

    condition {
      num_newer_versions = 3
      with_state         = "ARCHIVED"
    }
  }

  dynamic "lifecycle_rule" {
    for_each = var.current_object_retention_days == null ? [] : [var.current_object_retention_days]

    content {
      action {
        type = "Delete"
      }

      condition {
        age        = lifecycle_rule.value
        with_state = "LIVE"
      }
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}
