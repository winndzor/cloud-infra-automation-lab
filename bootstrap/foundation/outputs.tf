output "foundation_state_bucket_name" {
  description = "Human-owned bucket containing only foundation state."
  value       = module.foundation_state_bucket.name
}

output "lab_state_bucket_name" {
  description = "Workflow-owned bucket containing only lab workload state."
  value       = module.lab_state_bucket.name
}

output "lab_state_prefix" {
  description = "GCS object prefix reserved for the lab workload state."
  value       = var.lab_state_prefix
}

output "workload_identity_provider" {
  description = "Provider resource name consumed by google-github-actions/auth."
  value       = module.github_wif.provider_name
}

output "plan_service_account_email" {
  description = "Service account impersonated by the trusted plan workflow."
  value       = module.github_wif.plan_service_account_email
}

output "apply_service_account_email" {
  description = "Service account impersonated by the trusted apply workflow."
  value       = module.github_wif.apply_service_account_email
}

output "build_service_account_email" {
  description = "Service account impersonated by the trusted image build workflow."
  value       = module.github_wif.build_service_account_email
}

output "promote_service_account_email" {
  description = "Read-only service account impersonated by the trusted image promotion workflow."
  value       = module.github_wif.promote_service_account_email
}

output "runtime_service_account_email" {
  description = "Runtime identity used by the synthetic Cloud Run worker."
  value       = google_service_account.runtime.email
}

output "push_service_account_email" {
  description = "OIDC identity used by the authenticated Pub/Sub push subscription."
  value       = google_service_account.push.email
}

output "storage_service_account_email" {
  description = "Google-managed Cloud Storage service agent initialized for bucket notifications."
  value       = data.google_storage_project_service_account.storage.email_address
}

output "artifact_repository" {
  description = "Regional Docker repository used for synthetic worker images."
  value = {
    id       = google_artifact_registry_repository.worker.repository_id
    location = google_artifact_registry_repository.worker.location
    path     = "${google_artifact_registry_repository.worker.location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.worker.repository_id}"
  }
}

output "trusted_workflow_refs" {
  description = "Exact main-branch workflow refs allowed by the WIF bindings."
  value = {
    plan    = module.github_wif.plan_workflow_ref
    apply   = module.github_wif.apply_workflow_ref
    build   = module.github_wif.build_workflow_ref
    promote = module.github_wif.promote_workflow_ref
  }
}

output "enabled_services" {
  description = "APIs retained for the low-cost synthetic delivery slice."
  value       = sort(tolist(local.required_services))
}

output "state_safety_controls" {
  description = "Recovery and deletion controls applied to both state buckets."
  value = {
    foundation = module.foundation_state_bucket.safety_controls
    lab        = module.lab_state_bucket.safety_controls
  }
}
