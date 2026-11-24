# Container promotion

This runbook promotes one synthetic-worker image digest into Terraform without
rebuilding it. The image path and infrastructure apply path remain separate.

## Boundaries

- Dispatch both workflows only as GitHub owner ID `38678897` from `main`.
- The build identity may publish only to the dedicated Artifact Registry
  repository.
- The promotion identity has repository-scoped
  `roles/artifactregistry.reader` only.
- Promotion may change only `environments/lab/worker-release.json`.
- Repository Actions settings must allow workflow-created pull requests. The
  workflow creates a PR but never submits or bypasses a review.
- A release PR does not deploy. Use the existing saved-plan/exact-apply path.
- BuildKit SBOM/provenance are digest-bound evidence, not an independently
  signed attestation or an independent human approval.

## Build once

1. Dispatch **Synthetic worker image** on `main`.
2. Wait for its unit-test image, authenticated build, SBOM/provenance
   inspection, and manifest upload to succeed.
3. Record from the run summary:
   - source run ID and attempt;
   - exact `sha256:...` registry digest;
   - `synthetic-worker-build-<attempt>` artifact name;
   - GitHub artifact digest.
4. Do not rebuild between this step and promotion.

The seven-day artifact contains only `worker-build-manifest.json`. The image's
SPDX SBOM and SLSA provenance stay attached to its OCI index in Artifact
Registry. The manifest binds their canonical SHA-256 values to the image
digest, source commit, workflow ref/run/attempt, service Git tree, Dockerfile
hash, and `linux/amd64` platform.

## Verify and create the release PR

1. Dispatch **Promote synthetic worker image** on `main`.
2. Enter the recorded build run ID as `source_run_id`.
3. Enter the exact registry digest as `image_digest`; tags are invalid.
4. The verification job must prove:
   - owner dispatch and a successful source build on `main`;
   - one unexpired artifact with a service-recorded SHA-256 and exactly one
     expected manifest file;
   - matching source hashes, run metadata, and supplied image digest;
   - one `linux/amd64` runtime image;
   - non-empty BuildKit SPDX SBOM and SLSA provenance whose hashes match the
     manifest.
5. The cloud-free PR job writes a digest-derived branch, runs local contracts,
   explicitly dispatches `validate.yml` for that branch, waits for success, and
   opens the release PR.

Review that the PR changes only `worker-release.json`, references the same
source run/digest/evidence, and contains no floating deployment tag. Merge it
only after the explicit branch validation is green.

## Exact Terraform release

1. Dispatch **Terraform lab plan** from the merged `main`.
2. Review the rendered plan. It must show only an in-place Cloud Run worker
   image update, with no replacement, destroy, backend, project, IAM, or
   action against any resource owned by another state.
3. Record the plan run ID and saved-plan SHA-256 from its summary.
4. Dispatch **Terraform lab apply** with those exact values and its explicit
   confirmation.
5. Confirm exact-plan apply and the workflow's clean follow-up plan.

Stop if the plan is broader than the expected image-only update.

## Runtime proof

Follow `docs/runbooks/synthetic-smoke-test.md` with a new synthetic object.
Confirm the matching BigQuery row and structured Cloud Run log, then verify that
the deployed Cloud Run image reference resolves to the promoted digest.

In the build and promotion logs, retain the successful registry inspection of
the same digest and its attached SBOM/provenance. Finish with a clean remote
Terraform plan.

## Verification record

The source lab completed this flow end to end before publication of this sanitized portfolio copy: build evidence was bound to an immutable digest, promotion verified the same digest without rebuilding, Terraform planned an image-only in-place update, exact-plan apply completed, and the follow-up plan returned zero drift.

The public copy intentionally omits historical run IDs and deployment-specific proof values. Re-run the procedure above to create fresh evidence in a new environment.

## Expiry and recovery

- Build manifest artifacts expire after seven days. If one expires, perform a
  new build and promote its new digest; do not recreate evidence for an old
  digest.
- Promotion refuses an existing release branch. If a run failed after pushing
  but before opening the PR, inspect the branch and validation run. Delete the
  branch only when it contains solely the expected release record, then
  dispatch promotion again.
- A failed evidence check is a stop condition. Do not fall back to a tag,
  rebuild during promotion, or bypass explicit branch validation.
- A failed release apply is recovered through the existing Terraform runbook;
  promotion never writes Terraform state or Cloud Run directly.

This private GitHub Free repository has no required independent reviewer. The
same owner operates build, promotion, PR review, plan, and apply, so the chain
rehearses separation and immutable handoffs but does not claim separation of
duties.
