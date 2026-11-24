output "pool_name" {
  description = "Fully qualified workload identity pool name."
  value       = google_iam_workload_identity_pool.github.name
}

output "provider_name" {
  description = "Fully qualified GitHub OIDC provider name."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "plan_service_account_email" {
  description = "Service account impersonated by the trusted plan workflow."
  value       = google_service_account.plan.email
}

output "apply_service_account_email" {
  description = "Service account impersonated by the trusted apply workflow."
  value       = google_service_account.apply.email
}

output "build_service_account_email" {
  description = "Service account impersonated by the trusted container build workflow."
  value       = google_service_account.build.email
}

output "promote_service_account_email" {
  description = "Service account impersonated by the trusted container promotion workflow."
  value       = google_service_account.promote.email
}

output "attribute_condition" {
  description = "CEL condition enforced by the GitHub OIDC provider."
  value       = google_iam_workload_identity_pool_provider.github.attribute_condition
}

output "plan_workflow_ref" {
  description = "Exact workflow ref allowed to impersonate the plan identity."
  value       = local.plan_workflow_ref
}

output "apply_workflow_ref" {
  description = "Exact workflow ref allowed to impersonate the apply identity."
  value       = local.apply_workflow_ref
}

output "build_workflow_ref" {
  description = "Exact workflow ref allowed to impersonate the build identity."
  value       = local.build_workflow_ref
}

output "promote_workflow_ref" {
  description = "Exact workflow ref allowed to impersonate the promotion identity."
  value       = local.promote_workflow_ref
}
