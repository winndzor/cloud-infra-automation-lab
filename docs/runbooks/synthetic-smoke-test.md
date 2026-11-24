# Synthetic Delivery Smoke Test

## Scope

This runbook proves the lab-only path from the guarded input bucket through
Pub/Sub and authenticated Cloud Run to BigQuery. Use synthetic fixtures only.
The worker records object metadata and never reads object contents.

The commands intentionally add the Secret Manager version outside Terraform so
its value cannot enter Terraform configuration, a plan artifact, or state.

## Preconditions

1. The intended image digest and infrastructure are deployed from `main`.
2. The Terraform apply workflow has completed its zero-drift check.
3. `gcloud auth list` shows the sandbox operator account.
4. Every command names project `example-gcp-project` explicitly.

## Initialize synthetic runtime configuration

List enabled versions before adding one:

```shell
gcloud secrets versions list cloud-infra-lab-worker-config \
  --project=example-gcp-project \
  --filter='state=ENABLED'
```

If no enabled version exists, add the metadata-only fixture:

```shell
printf '%s' '{"mode":"metadata-only"}' \
  | gcloud secrets versions add cloud-infra-lab-worker-config \
      --project=example-gcp-project \
      --data-file=-
```

Do not put real credentials or customer configuration in this secret.

## Send one synthetic object

```shell
OBJECT_NAME="smoke/synthetic-proof-$(date -u +%Y%m%dT%H%M%SZ).json"
printf '%s\n' \
  '{"fixture":"synthetic-only","purpose":"end-to-end-proof"}' \
  | gcloud storage cp - \
      "gs://example-cloud-infra-lab-123456789012-input/${OBJECT_NAME}" \
      --project=example-gcp-project
```

Retain `OBJECT_NAME` for the evidence queries.

## Verify the processing path

Confirm exactly one metadata row:

```shell
bq query \
  --project_id=example-gcp-project \
  --use_legacy_sql=false \
  --format=prettyjson \
  "SELECT event_id, bucket, object_name, object_generation, object_size,
          event_time, processed_at
   FROM \`example-gcp-project.cloud_infra_lab.events\`
   WHERE object_name = '${OBJECT_NAME}'
   ORDER BY processed_at DESC"
```

Confirm the structured success log without reading object data:

```shell
gcloud logging read \
  "resource.type=\"cloud_run_revision\"
   AND resource.labels.service_name=\"cloud-infra-lab-worker\"
   AND jsonPayload.message=\"synthetic storage event processed\"
   AND jsonPayload.object_name=\"${OBJECT_NAME}\"" \
  --project=example-gcp-project \
  --freshness=1h \
  --limit=5 \
  --format='json(timestamp,severity,jsonPayload,resource.labels.revision_name)'
```

Confirm Pub/Sub uses the dedicated OIDC identity and Cloud Run remains bounded:

```shell
gcloud pubsub subscriptions describe cloud-infra-lab-worker-push \
  --project=example-gcp-project \
  --format='yaml(pushConfig,ackDeadlineSeconds,messageRetentionDuration,retryPolicy)'

gcloud run services describe cloud-infra-lab-worker \
  --project=example-gcp-project \
  --region=europe-central2 \
  --format='yaml(status.url,spec.template.spec.serviceAccountName,spec.template.metadata.annotations)'
```

Expected controls are the `cloud-infra-lab-push` OIDC identity, 10-minute
message retention, zero minimum instances, and one maximum instance.

## Confirm drift

Dispatch `terraform-plan.yml` from current `main`. A completed smoke test must
end with `No changes`. Do not dispatch apply for a no-change plan.

## Retention and cleanup

- Live input objects expire after one day and remain recoverable through GCS
  soft delete for seven days.
- Pub/Sub messages expire after 10 minutes.
- BigQuery partitions expire after one day.
- Untagged container versions are deleted after one day; only three recent
  versions are retained by the repository cleanup policy.
- Keep one enabled metadata-only secret version because the deployed worker
  resolves `latest` for every request.

## Verification record

The source lab completed the synthetic path end to end before publication of this portfolio copy: an object-finalize event reached Cloud Run through authenticated Pub/Sub push, produced a metadata-only BigQuery row and matching structured log, and the follow-up Terraform plan reported zero drift.

Historical run IDs, object names and deployment-specific proof values are intentionally omitted from the public copy.
