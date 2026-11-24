variable "project_id" {
  description = "Personal GCP project containing the synthetic lab slice."
  type        = string
}

variable "project_number" {
  description = "Immutable numeric GCP project identifier."
  type        = string
}

variable "region" {
  description = "Regional location used by Cloud Run and BigQuery."
  type        = string
}

variable "input_bucket_name" {
  description = "Existing guarded GCS bucket that emits object-finalize events."
  type        = string
}

variable "worker_image" {
  description = "Artifact Registry worker image pinned to an immutable digest."
  type        = string

  validation {
    condition = can(regex(
      "^europe-central2-docker\\.pkg\\.dev/example-gcp-project/cloud-infra-lab/event-metadata-worker@sha256:[0-9a-f]{64}$",
      var.worker_image,
    ))
    error_message = "The worker image must use the fixed lab repository and an immutable sha256 digest."
  }
}

variable "runtime_service_account_email" {
  description = "Foundation-owned Cloud Run runtime identity."
  type        = string
}

variable "push_service_account_email" {
  description = "Foundation-owned identity used for authenticated Pub/Sub push."
  type        = string
}

variable "labels" {
  description = "Common non-sensitive labels for resources that support labels."
  type        = map(string)
  default     = {}
}
