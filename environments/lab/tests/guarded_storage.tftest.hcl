mock_provider "google" {}

run "guarded_storage_contract" {
  command = plan

  assert {
    condition     = output.guarded_bucket_name == "example-cloud-infra-lab-123456789012-input"
    error_message = "The lab bucket must use its repository-specific synthetic name."
  }

  assert {
    condition     = output.guarded_bucket_safety_controls.force_destroy == false
    error_message = "The bucket must not destroy contained objects automatically."
  }

  assert {
    condition     = output.guarded_bucket_safety_controls.public_access_prevention == "enforced"
    error_message = "Public access prevention must be enforced."
  }

  assert {
    condition     = output.guarded_bucket_safety_controls.uniform_bucket_level_access == true
    error_message = "Uniform bucket-level access must be enabled."
  }

  assert {
    condition     = output.guarded_bucket_safety_controls.versioning_enabled == true
    error_message = "Object versioning must be enabled."
  }

  assert {
    condition = (
      output.guarded_bucket_safety_controls.soft_delete_retention_seconds >= 604800 &&
      output.guarded_bucket_safety_controls.current_object_retention_days == 1
    )
    error_message = "Objects must expire after one day while soft-deleted data retains a seven-day recovery window."
  }

  assert {
    condition = (
      output.event_metadata_worker.input_bucket == "example-cloud-infra-lab-123456789012-input" &&
      output.event_metadata_worker.worker_image == local.worker_release.image_ref &&
      local.worker_release.schema_version == 1 &&
      can(regex("^[0-9a-f]{40}([0-9a-f]{24})?$", local.worker_release.source_commit)) &&
      can(regex("^[1-9][0-9]*$", local.worker_release.source_run_id)) &&
      can(regex("^sha256:[0-9a-f]{64}$", local.worker_release.image_digest)) &&
      output.event_metadata_worker.cost_controls.minimum_instances == 0 &&
      output.event_metadata_worker.cost_controls.maximum_instances == 1
    )
    error_message = "The lab root must consume a source-bound release record and preserve scale-to-zero."
  }
}
