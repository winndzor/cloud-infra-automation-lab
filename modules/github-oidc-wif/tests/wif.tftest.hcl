mock_provider "google" {}

run "repository_scoped_wif_contract" {
  command = plan

  variables {
    project_id               = "example-gcp-project"
    pool_id                  = "github-cloud-infra-lab"
    provider_id              = "github-oidc"
    github_repository        = "winndzor/cloud-infra-automation-lab"
    github_repository_id     = "1470040849"
    github_owner_id          = "38678897"
    plan_service_account_id  = "cloud-infra-lab-plan"
    apply_service_account_id = "cloud-infra-lab-apply"
    build_service_account_id = "cloud-infra-lab-build"
    promote_service_account_id = (
      "cloud-infra-lab-promote"
    )
  }

  assert {
    condition = output.plan_workflow_ref == (
      "winndzor/cloud-infra-automation-lab/.github/workflows/terraform-plan.yml@refs/heads/main"
    )
    error_message = "The plan identity must trust only the main-branch plan workflow."
  }

  assert {
    condition = output.apply_workflow_ref == (
      "winndzor/cloud-infra-automation-lab/.github/workflows/terraform-apply.yml@refs/heads/main"
    )
    error_message = "The apply identity must trust only the main-branch apply workflow."
  }

  assert {
    condition = output.build_workflow_ref == (
      "winndzor/cloud-infra-automation-lab/.github/workflows/container-build.yml@refs/heads/main"
    )
    error_message = "The build identity must trust only the main-branch build workflow."
  }

  assert {
    condition = output.promote_workflow_ref == (
      "winndzor/cloud-infra-automation-lab/.github/workflows/container-promote.yml@refs/heads/main"
    ) && google_service_account.promote.account_id == "cloud-infra-lab-promote"
    error_message = "The promotion identity must trust only the main-branch promotion workflow."
  }

  assert {
    condition = alltrue([
      strcontains(output.attribute_condition, "assertion.repository == 'winndzor/cloud-infra-automation-lab'"),
      strcontains(output.attribute_condition, "assertion.repository_id == '1470040849'"),
      strcontains(output.attribute_condition, "assertion.repository_owner_id == '38678897'"),
      strcontains(output.attribute_condition, "assertion.actor_id == '38678897'"),
      strcontains(output.attribute_condition, "assertion.ref == 'refs/heads/main'"),
      strcontains(output.attribute_condition, "assertion.event_name == 'workflow_dispatch'"),
      strcontains(output.attribute_condition, "assertion.workflow_ref == 'winndzor/cloud-infra-automation-lab/.github/workflows/container-build.yml@refs/heads/main'"),
      strcontains(output.attribute_condition, "assertion.workflow_ref == 'winndzor/cloud-infra-automation-lab/.github/workflows/container-promote.yml@refs/heads/main'"),
    ])
    error_message = "The provider must enforce repository IDs, owner dispatch, main, and workflow_dispatch."
  }
}
