output "guarded_bucket_name" {
  description = "Globally unique name of the synthetic input bucket."
  value       = module.guarded_storage.name
}

output "guarded_bucket_safety_controls" {
  description = "Safety controls enforced on the synthetic input bucket."
  value       = module.guarded_storage.safety_controls
}

output "event_metadata_worker" {
  description = "Operational identifiers for the deployed synthetic delivery slice."
  value = {
    input_bucket     = module.guarded_storage.name
    topic            = module.event_metadata_worker.topic_name
    subscription     = module.event_metadata_worker.subscription_name
    service          = module.event_metadata_worker.service_name
    service_uri      = module.event_metadata_worker.service_uri
    bigquery_dataset = module.event_metadata_worker.dataset_id
    bigquery_table   = module.event_metadata_worker.table_id
    secret           = module.event_metadata_worker.secret_id
    worker_image     = module.event_metadata_worker.worker_image
    cost_controls    = module.event_metadata_worker.cost_controls
  }
}
