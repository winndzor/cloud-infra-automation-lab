output "topic_name" {
  description = "Pub/Sub topic receiving guarded bucket notifications."
  value       = google_pubsub_topic.storage_events.name
}

output "subscription_name" {
  description = "Authenticated push subscription delivering to Cloud Run."
  value       = google_pubsub_subscription.worker_push.name
}

output "service_name" {
  description = "Cloud Run worker service name."
  value       = google_cloud_run_v2_service.worker.name
}

output "service_uri" {
  description = "Cloud Run URI used by the authenticated push subscription."
  value       = google_cloud_run_v2_service.worker.uri
}

output "dataset_id" {
  description = "BigQuery dataset containing metadata-only synthetic rows."
  value       = google_bigquery_dataset.events.dataset_id
}

output "table_id" {
  description = "BigQuery table receiving metadata-only synthetic rows."
  value       = google_bigquery_table.events.table_id
}

output "secret_id" {
  description = "Secret Manager metadata resource; versions remain outside Terraform."
  value       = google_secret_manager_secret.worker_config.secret_id
}

output "worker_image" {
  description = "Immutable image digest deployed to Cloud Run."
  value       = var.worker_image
}

output "cost_controls" {
  description = "Low-cost retention and scaling controls."
  value = {
    topic_retention_seconds        = 600
    subscription_retention_seconds = 600
    minimum_instances              = 0
    maximum_instances              = 1
    partition_expiration_ms        = 86400000
  }
}
