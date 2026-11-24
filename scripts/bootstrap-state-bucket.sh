#!/usr/bin/env bash

set -euo pipefail

readonly PROJECT_ID="example-gcp-project"
readonly PROJECT_NUMBER="123456789012"
readonly STATE_BUCKET="example-cloud-infra-lab-123456789012-foundation-tfstate"
readonly LOCATION="EUROPE-CENTRAL2"
readonly EXPECTED_ACCOUNT="${GCP_BOOTSTRAP_ACCOUNT:?Set GCP_BOOTSTRAP_ACCOUNT to the expected active gcloud account}"

for command_name in gcloud terraform; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "${command_name}" >&2
    exit 1
  fi
done

active_account="$(gcloud auth list --filter=status:ACTIVE --format='value(account)')"
if [[ "${active_account}" != "${EXPECTED_ACCOUNT}" ]]; then
  printf 'Refusing bootstrap: active account is %s, expected %s.\n' \
    "${active_account:-<none>}" "${EXPECTED_ACCOUNT}" >&2
  exit 1
fi

actual_project_number="$(
  gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)'
)"
if [[ "${actual_project_number}" != "${PROJECT_NUMBER}" ]]; then
  printf 'Refusing bootstrap: project number is %s, expected %s.\n' \
    "${actual_project_number}" "${PROJECT_NUMBER}" >&2
  exit 1
fi

if gcloud storage buckets describe "gs://${STATE_BUCKET}" >/dev/null 2>&1; then
  printf 'Refusing bootstrap: gs://%s already exists; verify its owner before import.\n' \
    "${STATE_BUCKET}" >&2
  exit 1
fi

gcloud storage buckets create "gs://${STATE_BUCKET}" \
  --project="${PROJECT_ID}" \
  --location="${LOCATION}" \
  --uniform-bucket-level-access \
  --public-access-prevention \
  --soft-delete-duration=7d

gcloud storage buckets update "gs://${STATE_BUCKET}" \
  --versioning \
  --update-labels=environment=lab,managed_by=terraform,owner=winndzor,purpose=cloud-infra-lab-state

printf '\nCreated the empty state bucket with versioning enabled.\n'
printf 'Next: initialize bootstrap/foundation and import module.foundation_state_bucket.google_storage_bucket.this.\n'
