variable "project_id" {
  description = "Example GCP project identifier used by the public portfolio copy."
  type        = string
  default     = "example-gcp-project"

  validation {
    condition     = var.project_id == "example-gcp-project"
    error_message = "The public portfolio foundation is intentionally pinned to the example GCP project."
  }
}

variable "project_number" {
  description = "Example numeric GCP project identifier used by the public portfolio copy."
  type        = string
  default     = "123456789012"

  validation {
    condition     = var.project_number == "123456789012"
    error_message = "The foundation must not be redirected to another GCP project."
  }
}

variable "region" {
  description = "Default regional location for lab services."
  type        = string
  default     = "europe-central2"
}

variable "bucket_location" {
  description = "Location of both dedicated Terraform state buckets."
  type        = string
  default     = "EUROPE-CENTRAL2"
}

variable "foundation_state_bucket_name" {
  description = "Bucket dedicated to human-owned foundation state."
  type        = string
  default     = "example-cloud-infra-lab-123456789012-foundation-tfstate"

  validation {
    condition = (
      var.foundation_state_bucket_name == "example-cloud-infra-lab-123456789012-foundation-tfstate"
    )
    error_message = "The foundation state bucket must use its repository-specific fixed name."
  }
}

variable "lab_state_bucket_name" {
  description = "Bucket dedicated to workflow-owned lab state and locks."
  type        = string
  default     = "example-cloud-infra-lab-123456789012-lab-tfstate"

  validation {
    condition = (
      var.lab_state_bucket_name == "example-cloud-infra-lab-123456789012-lab-tfstate"
    )
    error_message = "The lab state bucket must use its repository-specific fixed name."
  }
}

variable "lab_state_prefix" {
  description = "Object prefix reserved for the lab workload state and lock."
  type        = string
  default     = "cloud-infra-lab/environments/lab/"
}

variable "lab_resource_bucket_name" {
  description = "Only workload bucket the apply identity may manage."
  type        = string
  default     = "example-cloud-infra-lab-123456789012-input"

  validation {
    condition     = var.lab_resource_bucket_name == "example-cloud-infra-lab-123456789012-input"
    error_message = "The apply boundary is fixed to the repository-specific synthetic input bucket."
  }
}

variable "artifact_repository_id" {
  description = "Regional Docker repository dedicated to synthetic lab images."
  type        = string
  default     = "cloud-infra-lab"

  validation {
    condition     = var.artifact_repository_id == "cloud-infra-lab"
    error_message = "The foundation may create only its fixed lab Artifact Registry repository."
  }
}

variable "github_repository" {
  description = "Exact GitHub repository trusted by workload identity federation."
  type        = string
  default     = "winndzor/cloud-infra-automation-lab"
}

variable "github_repository_id" {
  description = "Immutable GitHub repository ID."
  type        = string
  default     = "1470040849"
}

variable "github_owner_id" {
  description = "Immutable GitHub owner ID."
  type        = string
  default     = "38678897"
}

variable "common_labels" {
  description = "Base labels applied to both dedicated state buckets."
  type        = map(string)
  default = {
    environment = "lab"
    managed_by  = "terraform"
    owner       = "winndzor"
    purpose     = "cloud-infra-lab"
  }
}
