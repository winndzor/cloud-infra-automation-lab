# Event metadata worker

This small Cloud Run service accepts authenticated Pub/Sub push requests
generated from the lab's guarded GCS input bucket. It writes object metadata to
an expiring BigQuery table.

It never reads object contents. All fixtures must be synthetic.

## Runtime contract

- `EXPECTED_BUCKET`: exact allowed source bucket.
- `BIGQUERY_TABLE`: fully qualified destination table.
- `PROCESSING_CONFIG_SECRET_VERSION`: full resource name of the Secret Manager
  `latest` version. The worker fetches the JSON at request time, validates its
  metadata-only mode, and never logs or persists the value. This allows the
  service and secret metadata to be created in one exact Terraform apply while
  the version remains outside Terraform state.

Malformed events and events for another bucket are logged and acknowledged so
they do not become poison-message retry loops. BigQuery failures return an
error, allowing Pub/Sub to retry with the same message ID.

## Image contract

The Docker build runs the unit tests in its `test` stage. The owner-dispatched
build workflow publishes a commit tag to the dedicated Artifact Registry
repository once, attaches BuildKit SPDX SBOM and SLSA provenance, and records a
digest-bound build manifest.

The separate promotion workflow verifies that exact image and evidence with a
read-only identity, then opens a PR changing only
`environments/lab/worker-release.json`. Terraform consumes the record's
digest-only `image_ref`; promotion never rebuilds or deploys the worker.
