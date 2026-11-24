locals {
  topic_name        = "cloud-infra-lab-storage-events"
  subscription_name = "cloud-infra-lab-worker-push"
  service_name      = "cloud-infra-lab-worker"
  dataset_id        = "cloud_infra_lab"
  table_id          = "events"
  secret_id         = "cloud-infra-lab-worker-config"
}

resource "google_pubsub_topic" "storage_events" {
  project                    = var.project_id
  name                       = local.topic_name
  message_retention_duration = "600s"
  labels                     = var.labels
}

resource "google_pubsub_topic_iam_member" "storage_publisher" {
  project = var.project_id
  topic   = google_pubsub_topic.storage_events.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:service-${var.project_number}@gs-project-accounts.iam.gserviceaccount.com"
}

resource "google_storage_notification" "input_finalized" {
  bucket         = var.input_bucket_name
  payload_format = "JSON_API_V1"
  topic          = google_pubsub_topic.storage_events.id
  event_types    = ["OBJECT_FINALIZE"]

  custom_attributes = {
    source = "cloud-infra-lab"
  }

  depends_on = [google_pubsub_topic_iam_member.storage_publisher]
}

resource "google_bigquery_dataset" "events" {
  project                         = var.project_id
  dataset_id                      = local.dataset_id
  friendly_name                   = "Cloud infrastructure lab synthetic events"
  description                     = "Metadata-only rows produced by the event metadata worker."
  location                        = var.region
  default_partition_expiration_ms = 86400000
  delete_contents_on_destroy      = true
  max_time_travel_hours           = "48"
  labels                          = var.labels
}

resource "google_bigquery_table" "events" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.events.dataset_id
  table_id            = local.table_id
  description         = "Expiring metadata from synthetic object-finalize events."
  deletion_protection = false

  time_partitioning {
    type          = "DAY"
    field         = "processed_at"
    expiration_ms = 86400000
  }

  schema = jsonencode([
    {
      name = "event_id"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "bucket"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "object_name"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "object_generation"
      type = "STRING"
      mode = "NULLABLE"
    },
    {
      name = "object_size"
      type = "INTEGER"
      mode = "NULLABLE"
    },
    {
      name = "event_time"
      type = "TIMESTAMP"
      mode = "NULLABLE"
    },
    {
      name = "processed_at"
      type = "TIMESTAMP"
      mode = "REQUIRED"
    },
  ])
}

resource "google_bigquery_dataset_iam_member" "runtime_writer" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.events.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${var.runtime_service_account_email}"
}

resource "google_secret_manager_secret" "worker_config" {
  project             = var.project_id
  secret_id           = local.secret_id
  deletion_protection = false
  version_destroy_ttl = "86400s"
  labels              = var.labels

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_iam_member" "runtime_reader" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.worker_config.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.runtime_service_account_email}"
}

resource "google_cloud_run_v2_service" "worker" {
  project             = var.project_id
  name                = local.service_name
  location            = var.region
  description         = "Authenticated metadata-only event metadata worker."
  ingress             = "INGRESS_TRAFFIC_INTERNAL_ONLY"
  deletion_protection = false
  labels              = var.labels

  template {
    service_account                  = var.runtime_service_account_email
    timeout                          = "60s"
    max_instance_request_concurrency = 10

    scaling {
      min_instance_count = 0
      max_instance_count = 1
    }

    containers {
      image = var.worker_image

      ports {
        name           = "http1"
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle          = true
        startup_cpu_boost = false
      }

      env {
        name  = "EXPECTED_BUCKET"
        value = var.input_bucket_name
      }

      env {
        name  = "BIGQUERY_TABLE"
        value = "${var.project_id}.${google_bigquery_dataset.events.dataset_id}.${google_bigquery_table.events.table_id}"
      }

      env {
        name = "PROCESSING_CONFIG_SECRET_VERSION"
        value = (
          "${google_secret_manager_secret.worker_config.id}/versions/latest"
        )
      }

      startup_probe {
        initial_delay_seconds = 0
        timeout_seconds       = 2
        period_seconds        = 5
        failure_threshold     = 6

        http_get {
          path = "/health"
          port = 8080
        }
      }
    }
  }

  depends_on = [
    google_bigquery_dataset_iam_member.runtime_writer,
    google_secret_manager_secret_iam_member.runtime_reader,
  ]
}

resource "google_cloud_run_v2_service_iam_member" "push_invoker" {
  project  = var.project_id
  location = google_cloud_run_v2_service.worker.location
  name     = google_cloud_run_v2_service.worker.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${var.push_service_account_email}"
}

resource "google_pubsub_subscription" "worker_push" {
  project                    = var.project_id
  name                       = local.subscription_name
  topic                      = google_pubsub_topic.storage_events.id
  ack_deadline_seconds       = 60
  message_retention_duration = "600s"
  retain_acked_messages      = false
  labels                     = var.labels

  expiration_policy {
    ttl = ""
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "60s"
  }

  push_config {
    push_endpoint = google_cloud_run_v2_service.worker.uri

    oidc_token {
      service_account_email = var.push_service_account_email
      audience              = google_cloud_run_v2_service.worker.uri
    }
  }

  depends_on = [google_cloud_run_v2_service_iam_member.push_invoker]
}
