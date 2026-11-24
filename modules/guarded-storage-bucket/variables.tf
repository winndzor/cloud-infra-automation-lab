variable "project_id" {
  description = "Project that owns the bucket."
  type        = string
}

variable "name" {
  description = "Globally unique bucket name."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._-]{1,61}[a-z0-9]$", var.name))
    error_message = "Bucket names must be 3-63 characters and use lowercase letters, digits, dots, underscores, or hyphens."
  }
}

variable "location" {
  description = "GCS location for the bucket."
  type        = string
}

variable "labels" {
  description = "Labels applied to the bucket."
  type        = map(string)
  default     = {}
}

variable "current_object_retention_days" {
  description = "Optional number of days before live objects are deleted by lifecycle policy."
  type        = number
  default     = null

  validation {
    condition = (
      var.current_object_retention_days == null ||
      (
        var.current_object_retention_days >= 1 &&
        floor(var.current_object_retention_days) == var.current_object_retention_days
      )
    )
    error_message = "Current object retention must be null or a whole number of at least one day."
  }
}
