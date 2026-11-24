variable "project_id" {
  description = "GCP project that owns the workload identity resources."
  type        = string
}

variable "pool_id" {
  description = "Project-unique workload identity pool ID."
  type        = string
}

variable "provider_id" {
  description = "Pool-unique GitHub OIDC provider ID."
  type        = string
}

variable "github_repository" {
  description = "Exact GitHub repository in owner/name form."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must use the owner/name form."
  }
}

variable "github_repository_id" {
  description = "Immutable numeric GitHub repository ID."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.github_repository_id))
    error_message = "github_repository_id must contain only digits."
  }
}

variable "github_owner_id" {
  description = "Immutable numeric ID of the repository owner and only approved dispatcher."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.github_owner_id))
    error_message = "github_owner_id must contain only digits."
  }
}

variable "plan_workflow_path" {
  description = "Repository-relative path of the trusted plan workflow."
  type        = string
  default     = ".github/workflows/terraform-plan.yml"
}

variable "apply_workflow_path" {
  description = "Repository-relative path of the trusted apply workflow."
  type        = string
  default     = ".github/workflows/terraform-apply.yml"
}

variable "build_workflow_path" {
  description = "Repository-relative path of the trusted container build workflow."
  type        = string
  default     = ".github/workflows/container-build.yml"
}

variable "promote_workflow_path" {
  description = "Repository-relative path of the trusted container promotion workflow."
  type        = string
  default     = ".github/workflows/container-promote.yml"
}

variable "plan_service_account_id" {
  description = "Account ID for the plan-only Google service account."
  type        = string
}

variable "apply_service_account_id" {
  description = "Account ID for the apply Google service account."
  type        = string
}

variable "build_service_account_id" {
  description = "Account ID for the container build Google service account."
  type        = string
}

variable "promote_service_account_id" {
  description = "Account ID for the read-only container promotion Google service account."
  type        = string
}
