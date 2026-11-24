terraform {
  required_version = "~> 1.16.0"

  backend "gcs" {
    bucket = "bw-gcp-pattern-lab-339052684458-foundation-tfstate"
    prefix = "gcp-pattern-lab/bootstrap/foundation"
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.46.0"
    }
  }
}
