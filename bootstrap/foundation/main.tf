locals {
  plan_service_account_id    = "cloud-infra-lab-plan"
  apply_service_account_id   = "cloud-infra-lab-apply"
  build_service_account_id   = "cloud-infra-lab-build"
  promote_service_account_id = "cloud-infra-lab-promote"
  runtime_service_account_id = "cloud-infra-lab-worker"
  push_service_account_id    = "cloud-infra-lab-push"

  required_services = toset([
    "artifactregistry.googleapis.com",
    "bigquery.googleapis.com",
    "pubsub.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
  ])

  lab_resource_condition = join(" ", [
    "resource.type == \"cloudresourcemanager.googleapis.com/Project\" ||",
    "(resource.type == \"storage.googleapis.com/Bucket\" &&",
    "resource.name == \"projects/_/buckets/${var.lab_resource_bucket_name}\")",
  ])
  data_slice_condition = join(" ", [
    "resource.type == \"cloudresourcemanager.googleapis.com/Project\" ||",
    "resource.name.startsWith(\"projects/${var.project_id}/topics/cloud-infra-lab-\") ||",
    "resource.name.startsWith(\"projects/${var.project_id}/subscriptions/cloud-infra-lab-\") ||",
    "resource.name.startsWith(\"projects/${var.project_id}/datasets/cloud_infra_lab\") ||",
    "resource.name == \"projects/${var.project_id}/locations/${var.region}/services/cloud-infra-lab-worker\" ||",
    "resource.name == \"projects/${var.project_number}/secrets/cloud-infra-lab-worker-config\"",
  ])
  data_slice_create_condition = join(" || ", [
    "resource.name == \"projects/${var.project_id}\"",
    "resource.name == \"projects/${var.project_id}/locations/${var.region}\"",
  ])
  foundation_state_labels = merge(
    var.common_labels,
    { component = "foundation-state" },
  )
  lab_state_labels = merge(
    var.common_labels,
    { component = "lab-state" },
  )
}

resource "google_project_service" "required" {
  for_each = local.required_services

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

data "google_storage_project_service_account" "storage" {
  project = var.project_id
}

resource "google_artifact_registry_repository" "worker" {
  project       = var.project_id
  location      = var.region
  repository_id = var.artifact_repository_id
  description   = "Synthetic worker images for the personal Cloud infrastructure lab."
  format        = "DOCKER"
  labels        = var.common_labels

  cleanup_policies {
    id     = "delete-untagged-after-one-day"
    action = "DELETE"

    condition {
      tag_state  = "UNTAGGED"
      older_than = "86400s"
    }
  }

  cleanup_policies {
    id     = "keep-three-recent-versions"
    action = "KEEP"

    most_recent_versions {
      keep_count = 3
    }
  }

  depends_on = [google_project_service.required]
}

module "foundation_state_bucket" {
  source = "../../modules/guarded-storage-bucket"

  project_id = var.project_id
  name       = var.foundation_state_bucket_name
  location   = var.bucket_location
  labels     = local.foundation_state_labels
}

module "lab_state_bucket" {
  source = "../../modules/guarded-storage-bucket"

  project_id = var.project_id
  name       = var.lab_state_bucket_name
  location   = var.bucket_location
  labels     = local.lab_state_labels
}

module "github_wif" {
  source = "../../modules/github-oidc-wif"

  project_id               = var.project_id
  pool_id                  = "github-cloud-infra-lab"
  provider_id              = "github-oidc"
  github_repository        = var.github_repository
  github_repository_id     = var.github_repository_id
  github_owner_id          = var.github_owner_id
  plan_service_account_id  = local.plan_service_account_id
  apply_service_account_id = local.apply_service_account_id
  build_service_account_id = local.build_service_account_id
  promote_service_account_id = (
    local.promote_service_account_id
  )
}

resource "google_service_account" "runtime" {
  project      = var.project_id
  account_id   = local.runtime_service_account_id
  display_name = "Cloud infrastructure lab synthetic worker"
  description  = "Runtime identity for the event metadata Cloud Run worker."
}

resource "google_service_account" "push" {
  project      = var.project_id
  account_id   = local.push_service_account_id
  display_name = "Cloud infrastructure lab Pub/Sub push"
  description  = "OIDC identity used only for authenticated Pub/Sub push delivery."
}

resource "google_artifact_registry_repository_iam_member" "build_writer" {
  project    = var.project_id
  location   = google_artifact_registry_repository.worker.location
  repository = google_artifact_registry_repository.worker.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${module.github_wif.build_service_account_email}"
}

resource "google_artifact_registry_repository_iam_member" "apply_reader" {
  project    = var.project_id
  location   = google_artifact_registry_repository.worker.location
  repository = google_artifact_registry_repository.worker.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${module.github_wif.apply_service_account_email}"
}

resource "google_artifact_registry_repository_iam_member" "promote_reader" {
  project    = var.project_id
  location   = google_artifact_registry_repository.worker.location
  repository = google_artifact_registry_repository.worker.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${module.github_wif.promote_service_account_email}"
}

resource "google_service_account_iam_member" "apply_acts_as_runtime" {
  service_account_id = google_service_account.runtime.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${module.github_wif.apply_service_account_email}"
}

resource "google_service_account_iam_member" "apply_acts_as_push" {
  service_account_id = google_service_account.push.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${module.github_wif.apply_service_account_email}"
}

resource "google_service_account_iam_member" "pubsub_mints_push_tokens" {
  service_account_id = google_service_account.push.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:service-${var.project_number}@gcp-sa-pubsub.iam.gserviceaccount.com"

  depends_on = [google_project_service.required]
}

resource "google_project_iam_custom_role" "plan" {
  project     = var.project_id
  role_id     = "gcpPatternLabPlan"
  title       = "Cloud Infrastructure Lab Terraform Plan"
  description = "Read-only project permissions for the synthetic lab plan workflow."
  stage       = "GA"

  permissions = [
    "resourcemanager.projects.get",
    "storage.buckets.get",
    "storage.buckets.getIamPolicy",
    "storage.buckets.list",
  ]
}

resource "google_project_iam_custom_role" "apply" {
  project     = var.project_id
  role_id     = "gcpPatternLabApply"
  title       = "Cloud Infrastructure Lab Terraform Apply"
  description = "Bucket lifecycle permissions for the synthetic lab apply workflow."
  stage       = "GA"

  permissions = [
    "resourcemanager.projects.get",
    "storage.buckets.create",
    "storage.buckets.get",
    "storage.buckets.getIamPolicy",
    "storage.buckets.list",
    "storage.buckets.update",
  ]
}

resource "google_project_iam_custom_role" "data_plan" {
  project     = var.project_id
  role_id     = "gcpPatternLabDataPlan"
  title       = "Cloud Infrastructure Lab Data Slice Plan"
  description = "Read-only permissions for the synthetic data-delivery resources."
  stage       = "GA"

  permissions = [
    "bigquery.datasets.get",
    "bigquery.datasets.getIamPolicy",
    "bigquery.tables.get",
    "resourcemanager.projects.get",
    "secretmanager.secrets.get",
    "secretmanager.secrets.getIamPolicy",
  ]
}

resource "google_project_iam_custom_role" "data_apply" {
  project     = var.project_id
  role_id     = "gcpPatternLabDataApply"
  title       = "Cloud Infrastructure Lab Data Slice Apply"
  description = "Lifecycle permissions for the bounded synthetic data-delivery resources."
  stage       = "GA"

  permissions = [
    "bigquery.datasets.delete",
    "bigquery.datasets.get",
    "bigquery.datasets.getIamPolicy",
    "bigquery.datasets.setIamPolicy",
    "bigquery.datasets.update",
    "bigquery.tables.delete",
    "bigquery.tables.get",
    "bigquery.tables.update",
    "resourcemanager.projects.get",
    "secretmanager.secrets.delete",
    "secretmanager.secrets.get",
    "secretmanager.secrets.getIamPolicy",
    "secretmanager.secrets.setIamPolicy",
    "secretmanager.secrets.update",
  ]
}

resource "google_project_iam_custom_role" "data_create" {
  project     = var.project_id
  role_id     = "gcpPatternLabDataCreate"
  title       = "Cloud Infrastructure Lab Data Slice Create"
  description = "Create-only permissions required at parents without resource attributes."
  stage       = "GA"

  permissions = [
    "bigquery.datasets.create",
    "bigquery.tables.create",
    "pubsub.subscriptions.create",
    "pubsub.topics.attachSubscription",
    "pubsub.topics.create",
    "run.services.create",
    "secretmanager.secrets.create",
  ]
}

resource "google_project_iam_custom_role" "service_read" {
  project     = var.project_id
  role_id     = "gcpPatternLabServiceRead"
  title       = "Cloud Infrastructure Lab Service Read"
  description = "Read-only Pub/Sub and Cloud Run permissions where conditions are unsupported."
  stage       = "GA"

  permissions = [
    "pubsub.subscriptions.get",
    "pubsub.topics.get",
    "pubsub.topics.getIamPolicy",
    "run.services.get",
    "run.services.getIamPolicy",
  ]
}

resource "google_project_iam_custom_role" "pubsub_apply" {
  project     = var.project_id
  role_id     = "gcpPatternLabPubSubApply"
  title       = "Cloud Infrastructure Lab Pub/Sub Apply"
  description = "Pub/Sub lifecycle and IAM permissions where conditions are unsupported."
  stage       = "GA"

  permissions = [
    "pubsub.subscriptions.delete",
    "pubsub.subscriptions.get",
    "pubsub.subscriptions.update",
    "pubsub.topics.delete",
    "pubsub.topics.get",
    "pubsub.topics.getIamPolicy",
    "pubsub.topics.setIamPolicy",
    "pubsub.topics.update",
  ]
}

resource "google_project_iam_custom_role" "run_apply" {
  project     = var.project_id
  role_id     = "gcpPatternLabRunApply"
  title       = "Cloud Infrastructure Lab Cloud Run Apply"
  description = "Cloud Run lifecycle and IAM permissions where conditions are unsupported."
  stage       = "GA"

  permissions = [
    "run.operations.get",
    "run.services.delete",
    "run.services.get",
    "run.services.getIamPolicy",
    "run.services.setIamPolicy",
    "run.services.update",
  ]
}

resource "google_project_iam_member" "plan" {
  project = var.project_id
  role    = google_project_iam_custom_role.plan.name
  member  = "serviceAccount:${module.github_wif.plan_service_account_email}"

  condition {
    title       = "synthetic_bucket_read_only"
    description = "Read project metadata and only the synthetic input bucket."
    expression  = local.lab_resource_condition
  }
}

resource "google_project_iam_member" "apply" {
  project = var.project_id
  role    = google_project_iam_custom_role.apply.name
  member  = "serviceAccount:${module.github_wif.apply_service_account_email}"

  condition {
    title       = "synthetic_bucket_only"
    description = "Create buckets in the project but update only the synthetic input bucket."
    expression  = local.lab_resource_condition
  }
}

resource "google_project_iam_member" "data_plan" {
  project = var.project_id
  role    = google_project_iam_custom_role.data_plan.name
  member  = "serviceAccount:${module.github_wif.plan_service_account_email}"

  condition {
    title       = "synthetic_data_slice_read_only"
    description = "Read only the bounded synthetic data-delivery resources."
    expression  = local.data_slice_condition
  }
}

resource "google_project_iam_member" "data_apply" {
  project = var.project_id
  role    = google_project_iam_custom_role.data_apply.name
  member  = "serviceAccount:${module.github_wif.apply_service_account_email}"

  condition {
    title       = "synthetic_data_slice_only"
    description = "Manage only the bounded synthetic data-delivery resources."
    expression  = local.data_slice_condition
  }
}

resource "google_project_iam_member" "data_apply_create" {
  project = var.project_id
  role    = google_project_iam_custom_role.data_apply.name
  member  = "serviceAccount:${module.github_wif.apply_service_account_email}"

  condition {
    title       = "synthetic_data_slice_create_parents"
    description = "Create bounded service resources at the project or fixed regional parent."
    expression  = local.data_slice_create_condition
  }
}

resource "google_project_iam_member" "data_create" {
  project = var.project_id
  role    = google_project_iam_custom_role.data_create.name
  member  = "serviceAccount:${module.github_wif.apply_service_account_email}"
}

resource "google_project_iam_member" "service_read" {
  project = var.project_id
  role    = google_project_iam_custom_role.service_read.name
  member  = "serviceAccount:${module.github_wif.plan_service_account_email}"
}

resource "google_project_iam_member" "pubsub_apply" {
  project = var.project_id
  role    = google_project_iam_custom_role.pubsub_apply.name
  member  = "serviceAccount:${module.github_wif.apply_service_account_email}"
}

resource "google_project_iam_member" "run_apply" {
  project = var.project_id
  role    = google_project_iam_custom_role.run_apply.name
  member  = "serviceAccount:${module.github_wif.apply_service_account_email}"
}

resource "google_storage_bucket_iam_member" "plan_state" {
  bucket = module.lab_state_bucket.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${module.github_wif.plan_service_account_email}"
}

resource "google_storage_bucket_iam_member" "apply_state" {
  bucket = module.lab_state_bucket.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${module.github_wif.apply_service_account_email}"
}
