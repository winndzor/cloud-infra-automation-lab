# Architecture

## Purpose

This lab exercises infrastructure delivery and operational controls against low-cost, synthetic resources in a personal GCP sandbox. It is intentionally small enough to understand end to end while still including state, identity, CI/CD, container promotion, event delivery, runtime configuration and observability.

## Runtime vertical slice

```text
Synthetic object
  -> guarded GCS input bucket
  -> Pub/Sub object-finalize event
  -> authenticated Cloud Run worker
  -> metadata-only BigQuery row
```

Secret Manager holds the runtime processing mode without placing secret values in Terraform state. Cloud Run scales to zero and is capped at one instance. Storage objects and BigQuery partitions expire quickly, Pub/Sub retention is short, and Artifact Registry cleanup keeps the image footprint bounded.

The source lab completed an end-to-end proof with synthetic data: object finalization triggered authenticated Pub/Sub push, the worker read metadata-only configuration from Secret Manager, and a matching BigQuery row plus structured success log were observed. The worker does not read object contents.

## Delivery architecture

The delivery design separates validation, planning, applying, building and promotion:

- Pull requests run credential-free formatting, initialization, validation and tests.
- GitHub Actions obtains short-lived GCP credentials through Workload Identity Federation only for explicitly cloud-facing workflows.
- Plan and apply use separate service accounts and separate IAM scopes.
- The plan workflow uploads a short-lived artifact containing the saved binary plan, rendered plan text and a manifest with source metadata and SHA-256.
- The apply workflow validates source run metadata, current `main`, expected artifact files, manifest content and an operator-supplied digest before cloud authentication.
- Apply executes the exact binary plan rather than replanning.
- A post-apply plan verifies zero drift.

The foundation is isolated from the workload:

- `bootstrap/foundation` owns state buckets, WIF, service accounts, custom IAM roles and Artifact Registry.
- The foundation is bootstrapped by a human recovery owner rather than the workflow identities it creates.
- Foundation state and workload state use separate buckets.
- Workflow identities can access only workload state; they cannot read or modify foundation state.
- WIF trust is restricted to the intended GitHub repository, actor/owner IDs and workflow refs on `main`.

## Immutable image promotion

The worker image is built once for `linux/amd64`. BuildKit attaches SPDX SBOM and SLSA provenance evidence to the OCI image index.

The build produces a JSON manifest binding:

- source commit and workflow run;
- service-directory Git tree;
- Dockerfile SHA-256;
- image digest and canonical image reference;
- platform;
- SBOM and provenance hashes.

Promotion is a separate workflow using a read-only Artifact Registry identity. It verifies the source build, artifact digest, manifest metadata, supplied image digest, platform and non-empty SBOM/provenance before creating a release change. Promotion never rebuilds the image.

Terraform deploys the immutable digest recorded in the release file, so image publication and infrastructure deployment remain separate concerns.

## Identity model

The design avoids long-lived service-account keys.

```text
GitHub Actions
  -> GitHub OIDC token
  -> GCP Workload Identity Federation
  -> short-lived plan / apply / build / promote service account
```

Separate identities intentionally reduce blast radius:

- **plan**: read-only infrastructure discovery plus workload-state locking access;
- **apply**: bounded mutation permissions for the lab workload plus state locking;
- **build**: Artifact Registry writer only for the lab image repository;
- **promote**: Artifact Registry reader only;
- **runtime**: only permissions required by the Cloud Run worker;
- **push**: OIDC identity used by Pub/Sub to invoke Cloud Run.

Where broad predefined roles would be excessive, the foundation uses custom roles and IAM conditions to narrow access to the synthetic resource set.

## State ownership

State is treated as an operational asset, not an implementation detail.

- Foundation and workload state are separated.
- State buckets use uniform bucket-level access, public-access prevention, versioning, soft deletion, `force_destroy=false` and Terraform `prevent_destroy`.
- The supported GCS backend requires create/delete access for lock objects, so workload identities need object-level write access to the workload state bucket even when infrastructure permissions are otherwise read-only.
- A physical resource must have exactly one state owner.
- Import requires an ownership preflight and rollback plan.

See `docs/runbooks/state-ownership.md` for the operational procedure.

## Cost boundary

The workload deliberately excludes expensive always-on infrastructure such as GKE, Cloud SQL, Kafka, Cloud NAT and permanent VMs.

Cost controls include:

- Cloud Run scale-to-zero;
- one maximum worker instance;
- short Pub/Sub retention;
- one-day storage/BigQuery retention for synthetic data;
- Artifact Registry cleanup;
- small synthetic payloads;
- budget alerts as notification only.

Budget alerts are not treated as hard spending caps; architecture and quotas provide the real boundary.

## Governance limitation

The source lab used a private GitHub Free repository. That environment could not enforce the same branch protection, required reviewer or private-attestation controls available in larger GitHub plans.

The repository therefore documents an explicit self-operated handoff rather than claiming independent approval. In a team/enterprise setting the same design should move the manual gate behind protected environments, required reviewers and repository rulesets.

## Transferable patterns

Although this implementation uses GCP, the patterns are provider-independent:

- GitHub OIDC federation instead of static credentials;
- isolated remote state and explicit ownership;
- plan/apply separation;
- immutable artifact promotion;
- least-privilege deployment identities;
- event-driven workloads;
- bounded runtime cost;
- operator-focused runbooks and recovery procedures.
