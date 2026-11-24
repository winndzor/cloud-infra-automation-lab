mock_provider "google" {}

run "event_metadata_worker_contract" {
  command = plan

  variables {
    project_id     = "example-gcp-project"
    project_number = "123456789012"
    region         = "europe-central2"
    input_bucket_name = (
      "example-cloud-infra-lab-123456789012-input"
    )
    worker_image = (
      "europe-central2-docker.pkg.dev/example-gcp-project/cloud-infra-lab/event-metadata-worker@sha256:ede1aa048574efe808152b86d7f06a11158d094f2bb2d20d9957b1ba5dac4760"
    )
    runtime_service_account_email = (
      "cloud-infra-lab-worker@example-gcp-project.iam.gserviceaccount.com"
    )
    push_service_account_email = (
      "cloud-infra-lab-push@example-gcp-project.iam.gserviceaccount.com"
    )
  }

  assert {
    condition = (
      google_storage_notification.input_finalized.bucket == "example-cloud-infra-lab-123456789012-input" &&
      length(google_storage_notification.input_finalized.event_types) == 1 &&
      contains(google_storage_notification.input_finalized.event_types, "OBJECT_FINALIZE") &&
      google_storage_notification.input_finalized.payload_format == "JSON_API_V1"
    )
    error_message = "Only finalized objects in the guarded input bucket may enter the event path."
  }

  assert {
    condition = (
      google_pubsub_topic.storage_events.message_retention_duration == "600s" &&
      google_pubsub_subscription.worker_push.message_retention_duration == "600s" &&
      google_pubsub_subscription.worker_push.retain_acked_messages == false &&
      google_pubsub_subscription.worker_push.push_config[0].oidc_token[0].service_account_email == "cloud-infra-lab-push@example-gcp-project.iam.gserviceaccount.com"
    )
    error_message = "Pub/Sub must use short retention and the dedicated authenticated push identity."
  }

  assert {
    condition = (
      google_cloud_run_v2_service.worker.ingress == "INGRESS_TRAFFIC_INTERNAL_ONLY" &&
      google_cloud_run_v2_service.worker.template[0].service_account == "cloud-infra-lab-worker@example-gcp-project.iam.gserviceaccount.com" &&
      google_cloud_run_v2_service.worker.template[0].scaling[0].min_instance_count == 0 &&
      google_cloud_run_v2_service.worker.template[0].scaling[0].max_instance_count == 1 &&
      strcontains(
        google_cloud_run_v2_service.worker.template[0].containers[0].image,
        "@sha256:",
      )
    )
    error_message = "Cloud Run must be internal, scale to zero, use one maximum instance, and deploy by digest."
  }

  assert {
    condition = (
      google_bigquery_dataset.events.default_partition_expiration_ms == 86400000 &&
      google_bigquery_dataset.events.max_time_travel_hours == "48" &&
      google_bigquery_table.events.time_partitioning[0].expiration_ms == 86400000 &&
      google_bigquery_table.events.deletion_protection == false
    )
    error_message = "BigQuery metadata must use one-day partition expiry and minimum time travel."
  }

  assert {
    condition = (
      google_secret_manager_secret.worker_config.secret_id == "cloud-infra-lab-worker-config" &&
      google_secret_manager_secret_iam_member.runtime_reader.role == "roles/secretmanager.secretAccessor" &&
      google_bigquery_dataset_iam_member.runtime_writer.role == "roles/bigquery.dataEditor"
    )
    error_message = "Runtime access must be scoped to the one secret and one dataset."
  }

  assert {
    condition = (
      output.cost_controls.minimum_instances == 0 &&
      output.cost_controls.maximum_instances == 1 &&
      output.cost_controls.partition_expiration_ms == 86400000
    )
    error_message = "The module must expose its low-cost operational boundaries."
  }
}
