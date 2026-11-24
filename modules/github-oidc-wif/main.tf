locals {
  github_ref        = "refs/heads/main"
  plan_workflow_ref = "${var.github_repository}/${var.plan_workflow_path}@${local.github_ref}"
  apply_workflow_ref = (
    "${var.github_repository}/${var.apply_workflow_path}@${local.github_ref}"
  )
  build_workflow_ref = (
    "${var.github_repository}/${var.build_workflow_path}@${local.github_ref}"
  )
  promote_workflow_ref = (
    "${var.github_repository}/${var.promote_workflow_path}@${local.github_ref}"
  )

  principal_set_prefix = (
    "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}"
  )
}

resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = var.pool_id
  display_name              = "GitHub GCP pattern lab"
  description               = "Trust boundary for owner-dispatched workflows in one private repository."
  disabled                  = false
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = var.provider_id
  display_name                       = "GitHub Actions OIDC"
  description                        = "Accepts only owner-dispatched main-branch plan, apply, build, and promotion workflows."

  attribute_mapping = {
    "google.subject"                = "assertion.sub"
    "attribute.actor_id"            = "assertion.actor_id"
    "attribute.event_name"          = "assertion.event_name"
    "attribute.ref"                 = "assertion.ref"
    "attribute.repository"          = "assertion.repository"
    "attribute.repository_id"       = "assertion.repository_id"
    "attribute.repository_owner_id" = "assertion.repository_owner_id"
    "attribute.workflow_ref"        = "assertion.workflow_ref"
  }

  attribute_condition = join(" ", [
    "assertion.repository == '${var.github_repository}' &&",
    "assertion.repository_id == '${var.github_repository_id}' &&",
    "assertion.repository_owner_id == '${var.github_owner_id}' &&",
    "assertion.actor_id == '${var.github_owner_id}' &&",
    "assertion.ref == '${local.github_ref}' &&",
    "assertion.event_name == 'workflow_dispatch' &&",
    "(assertion.workflow_ref == '${local.plan_workflow_ref}' ||",
    "assertion.workflow_ref == '${local.apply_workflow_ref}' ||",
    "assertion.workflow_ref == '${local.build_workflow_ref}' ||",
    "assertion.workflow_ref == '${local.promote_workflow_ref}')",
  ])

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account" "plan" {
  project      = var.project_id
  account_id   = var.plan_service_account_id
  display_name = "GCP pattern lab Terraform plan"
  description  = "Short-lived GitHub identity for remote Terraform plans."
}

resource "google_service_account" "apply" {
  project      = var.project_id
  account_id   = var.apply_service_account_id
  display_name = "GCP pattern lab Terraform apply"
  description  = "Short-lived GitHub identity for owner-dispatched exact-plan applies."
}

resource "google_service_account" "build" {
  project      = var.project_id
  account_id   = var.build_service_account_id
  display_name = "GCP pattern lab container build"
  description  = "Short-lived GitHub identity for owner-dispatched image publication."
}

resource "google_service_account" "promote" {
  project      = var.project_id
  account_id   = var.promote_service_account_id
  display_name = "GCP pattern lab container promotion"
  description  = "Short-lived read-only identity for owner-dispatched image verification."
}

resource "google_service_account_iam_member" "plan_wif" {
  service_account_id = google_service_account.plan.name
  role               = "roles/iam.workloadIdentityUser"
  member = join("/", [
    local.principal_set_prefix,
    "attribute.workflow_ref",
    local.plan_workflow_ref,
  ])
}

resource "google_service_account_iam_member" "apply_wif" {
  service_account_id = google_service_account.apply.name
  role               = "roles/iam.workloadIdentityUser"
  member = join("/", [
    local.principal_set_prefix,
    "attribute.workflow_ref",
    local.apply_workflow_ref,
  ])
}

resource "google_service_account_iam_member" "build_wif" {
  service_account_id = google_service_account.build.name
  role               = "roles/iam.workloadIdentityUser"
  member = join("/", [
    local.principal_set_prefix,
    "attribute.workflow_ref",
    local.build_workflow_ref,
  ])
}

resource "google_service_account_iam_member" "promote_wif" {
  service_account_id = google_service_account.promote.name
  role               = "roles/iam.workloadIdentityUser"
  member = join("/", [
    local.principal_set_prefix,
    "attribute.workflow_ref",
    local.promote_workflow_ref,
  ])
}
