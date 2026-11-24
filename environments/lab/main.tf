locals {
  worker_release = jsondecode(file("${path.module}/worker-release.json"))
  worker_image   = local.worker_release.image_ref
}

check "worker_release_contract" {
  assert {
    condition = (
      local.worker_release.schema_version == 1 &&
      local.worker_release.repository == "winndzor/cloud-infra-automation-lab" &&
      local.worker_release.source_workflow_ref == "winndzor/cloud-infra-automation-lab/.github/workflows/container-build.yml@refs/heads/main" &&
      can(regex("^[0-9a-f]{40}([0-9a-f]{24})?$", local.worker_release.source_commit)) &&
      can(regex("^[1-9][0-9]*$", local.worker_release.source_run_id)) &&
      can(regex("^[1-9][0-9]*$", local.worker_release.source_run_attempt)) &&
      can(regex("^sha256:[0-9a-f]{64}$", local.worker_release.image_digest)) &&
      local.worker_release.image_ref == "europe-central2-docker.pkg.dev/example-gcp-project/cloud-infra-lab/event-metadata-worker@${local.worker_release.image_digest}"
    )
    error_message = "worker-release.json must identify a trusted digest-only build and its source metadata."
  }
}

module "guarded_storage" {
  source = "../../modules/guarded-storage-bucket"

  project_id                    = var.project_id
  name                          = var.bucket_name
  location                      = var.bucket_location
  current_object_retention_days = 1
  labels                        = var.common_labels
}

module "event_metadata_worker" {
  source = "../../modules/event-metadata-worker"

  project_id     = var.project_id
  project_number = var.project_number
  region         = var.region
  input_bucket_name = (
    module.guarded_storage.name
  )
  worker_image = local.worker_image
  runtime_service_account_email = (
    "cloud-infra-lab-worker@example-gcp-project.iam.gserviceaccount.com"
  )
  push_service_account_email = (
    "cloud-infra-lab-push@example-gcp-project.iam.gserviceaccount.com"
  )
  labels = merge(
    var.common_labels,
    { component = "event-metadata-worker" },
  )
}
