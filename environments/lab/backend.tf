terraform {
  backend "gcs" {
    bucket = "example-cloud-infra-lab-123456789012-lab-tfstate"
    prefix = "cloud-infra-lab/environments/lab"
  }
}
