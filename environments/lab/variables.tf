variable "project_id" {
  description = "Example GCP project identifier used by the public portfolio copy."
  type        = string
  default     = "example-gcp-project"

  validation {
    condition     = var.project_id == "example-gcp-project"
    error_message = "This lab root is intentionally restricted to the public example-gcp-project project."
  }
}

variable "project_number" {
  description = "Example numeric GCP project identifier used by the public portfolio copy."
  type        = string
  default     = "123456789012"

  validation {
    condition     = var.project_number == "123456789012"
    error_message = "The lab root must not be redirected to another GCP project."
  }
}

variable "region" {
  description = "Default regional location for lab services."
  type        = string
  default     = "europe-central2"
}

variable "bucket_location" {
  description = "Location of the proposed guarded storage bucket."
  type        = string
  default     = "EUROPE-CENTRAL2"
}

variable "bucket_name" {
  description = "Globally unique synthetic bucket name reserved for this repository."
  type        = string
  default     = "example-cloud-infra-lab-123456789012-input"
}

variable "common_labels" {
  description = "Labels applied to every supported lab resource."
  type        = map(string)
  default = {
    environment = "lab"
    managed_by  = "terraform"
    owner       = "winndzor"
    purpose     = "cloud-infra-lab"
  }
}
