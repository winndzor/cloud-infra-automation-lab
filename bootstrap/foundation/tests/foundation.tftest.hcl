mock_provider "google" {}

run "delivery_foundation_contract" {
  command = plan

  assert {
    condition = (
      output.foundation_state_bucket_name == "example-cloud-infra-lab-123456789012-foundation-tfstate" &&
      output.lab_state_bucket_name == "example-cloud-infra-lab-123456789012-lab-tfstate"
    )
    error_message = "Foundation and workflow state must use separate dedicated buckets."
  }

  assert {
    condition     = output.lab_state_prefix == "cloud-infra-lab/environments/lab/"
    error_message = "The workload state must use its repository-specific prefix."
  }

  assert {
    condition = output.trusted_workflow_refs.plan == (
      "winndzor/cloud-infra-automation-lab/.github/workflows/terraform-plan.yml@refs/heads/main"
    )
    error_message = "Only the main-branch plan workflow may use the plan identity."
  }

  assert {
    condition = output.trusted_workflow_refs.apply == (
      "winndzor/cloud-infra-automation-lab/.github/workflows/terraform-apply.yml@refs/heads/main"
    )
    error_message = "Only the main-branch apply workflow may use the apply identity."
  }

  assert {
    condition = output.trusted_workflow_refs.build == (
      "winndzor/cloud-infra-automation-lab/.github/workflows/container-build.yml@refs/heads/main"
    )
    error_message = "Only the main-branch container build workflow may use the build identity."
  }

  assert {
    condition = output.trusted_workflow_refs.promote == (
      "winndzor/cloud-infra-automation-lab/.github/workflows/container-promote.yml@refs/heads/main"
    )
    error_message = "Only the main-branch promotion workflow may use the read-only promotion identity."
  }

  assert {
    condition = (
      output.artifact_repository.id == "cloud-infra-lab" &&
      output.artifact_repository.location == "europe-central2" &&
      google_service_account.runtime.account_id == "cloud-infra-lab-worker" &&
      google_service_account.push.account_id == "cloud-infra-lab-push" &&
      google_artifact_registry_repository_iam_member.promote_reader.role == "roles/artifactregistry.reader" &&
      data.google_storage_project_service_account.storage.project == "example-gcp-project"
    )
    error_message = "Foundation image, runtime, and Google-managed Storage identities must be initialized in the lab project."
  }

  assert {
    condition = alltrue([
      contains(output.enabled_services, "artifactregistry.googleapis.com"),
      contains(output.enabled_services, "bigquery.googleapis.com"),
      contains(output.enabled_services, "pubsub.googleapis.com"),
      contains(output.enabled_services, "run.googleapis.com"),
      contains(output.enabled_services, "secretmanager.googleapis.com"),
      length(google_artifact_registry_repository.worker.cleanup_policies) == 2,
    ])
    error_message = "The delivery slice must enable only its required APIs and bound image retention."
  }

  assert {
    condition = alltrue([
      output.state_safety_controls.foundation.force_destroy == false,
      output.state_safety_controls.foundation.public_access_prevention == "enforced",
      output.state_safety_controls.foundation.uniform_bucket_level_access == true,
      output.state_safety_controls.foundation.versioning_enabled == true,
      output.state_safety_controls.foundation.soft_delete_retention_seconds >= 604800,
      output.state_safety_controls.foundation.current_object_retention_days == null,
      output.state_safety_controls.lab.force_destroy == false,
      output.state_safety_controls.lab.public_access_prevention == "enforced",
      output.state_safety_controls.lab.uniform_bucket_level_access == true,
      output.state_safety_controls.lab.versioning_enabled == true,
      output.state_safety_controls.lab.soft_delete_retention_seconds >= 604800,
      output.state_safety_controls.lab.current_object_retention_days == null,
    ])
    error_message = "Both state buckets must retain every required recovery/access control without live-object expiration."
  }

  assert {
    condition = (
      contains(google_project_iam_custom_role.plan.permissions, "storage.buckets.get") &&
      !contains(google_project_iam_custom_role.plan.permissions, "storage.buckets.create") &&
      !contains(google_project_iam_custom_role.plan.permissions, "bigquery.tables.get") &&
      !contains(google_project_iam_custom_role.data_apply.permissions, "run.services.update") &&
      !contains(google_project_iam_custom_role.data_apply.permissions, "pubsub.topics.create") &&
      !contains(google_project_iam_custom_role.data_apply.permissions, "bigquery.tables.create") &&
      contains(google_project_iam_custom_role.data_create.permissions, "pubsub.topics.attachSubscription") &&
      contains(google_project_iam_custom_role.data_create.permissions, "pubsub.topics.create") &&
      contains(google_project_iam_custom_role.data_create.permissions, "bigquery.tables.create") &&
      contains(google_project_iam_custom_role.data_create.permissions, "run.services.create") &&
      length(google_project_iam_custom_role.data_create.permissions) == 7 &&
      contains(google_project_iam_custom_role.service_read.permissions, "run.services.get") &&
      !contains(google_project_iam_custom_role.service_read.permissions, "run.services.update") &&
      contains(google_project_iam_custom_role.pubsub_apply.permissions, "pubsub.topics.setIamPolicy") &&
      contains(google_project_iam_custom_role.run_apply.permissions, "run.services.update") &&
      !contains(google_project_iam_custom_role.apply.permissions, "storage.buckets.delete") &&
      !contains(google_project_iam_custom_role.data_apply.permissions, "storage.buckets.delete") &&
      !contains(google_project_iam_custom_role.data_apply.permissions, "iam.serviceAccountKeys.create")
    )
    error_message = "Bucket and data-slice permissions must remain separate without bucket deletion or keys."
  }

  assert {
    condition = (
      strcontains(
        google_project_iam_member.data_apply_create.condition[0].expression,
        "resource.name == \"projects/example-gcp-project\"",
      ) &&
      strcontains(
        google_project_iam_member.data_apply_create.condition[0].expression,
        "resource.name == \"projects/example-gcp-project/locations/europe-central2\"",
      )
    )
    error_message = "Create permissions must be limited to the fixed project and regional parents."
  }
}
