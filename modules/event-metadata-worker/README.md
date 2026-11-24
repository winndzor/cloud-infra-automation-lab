# Event metadata module

This module owns the low-cost event path from the existing guarded input bucket
to a metadata-only BigQuery table:

1. GCS object-finalize notification to Pub/Sub.
2. Authenticated Pub/Sub push to an internal-ingress Cloud Run service.
3. Runtime Secret Manager read and BigQuery metadata insert.

The module creates Secret Manager metadata only. A synthetic secret version is
added by an owner outside Terraform state after apply.

Cost boundaries are explicit: ten-minute Pub/Sub retention, Cloud Run
scale-to-zero with one maximum instance, and one-day BigQuery partition
expiration.
