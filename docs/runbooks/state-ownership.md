# State Ownership Runbook

## Purpose

This runbook exists because an existing cloud resource is not necessarily unmanaged. A safe import requires proving that no other Terraform/OpenTofu state already owns the physical resource.

## Non-negotiable rules

1. Every physical resource has exactly one authoritative state owner.
2. Never import a resource until existing state ownership is verified.
3. Never run a local apply while state ownership is unresolved.
4. Never commit state, saved plans, credentials or secret values.
5. State migration and resource refactoring are separate changes.
6. Keep a rollback path before changing state ownership.

## Canonical backends

The source lab separates foundation state from workflow-managed workload state:

- the **foundation state bucket** contains only `bootstrap/foundation` state and is controlled by the human recovery owner;
- the **workload state bucket** contains only `environments/lab` state and is accessible to plan/apply automation identities.

Both state buckets enforce:

- uniform bucket-level access;
- public-access prevention;
- object versioning;
- seven-day soft deletion;
- `force_destroy=false`;
- Terraform `prevent_destroy`.

A GCS backend creates and deletes lock objects. Therefore the plan/apply identities need object-level write access to the workload state bucket even when their infrastructure permissions are otherwise restricted.

## Bootstrap sequence

Run bootstrap only from a reviewed, clean commit.

1. Confirm the active cloud identity and target project.
2. Search candidate state backends and existing Terraform owners for the resource names involved.
3. Create the dedicated foundation-state bucket with the bootstrap script. The script must refuse to adopt an unexpected existing bucket.
4. Initialize the foundation root against the new remote backend.
5. Import only the bucket that was intentionally pre-created by the bootstrap step.
6. Save and review a foundation plan.
7. Apply that exact reviewed plan.
8. Verify state location, bucket controls, WIF trust, IAM bindings and absence of local state.
9. Remove any temporary human ADC used for bootstrap.

If bucket creation succeeds but a later step fails, do not recreate or rename the bucket. Treat it as the known pre-created import candidate and resume only after verifying project, controls and state ownership.

## Import preflight

Before **any** import:

1. Identify the physical resource and intended Terraform address.
2. Search all known state backends and orchestrators for an existing owner.
3. Inspect repository history if ownership provenance is unclear.
4. Stop if more than one owner is possible.
5. Capture authoritative state backup/rollback information where available.
6. Import only after review.
7. Run a plan immediately after import and reconcile configuration to cloud reality.
8. Verify that exactly one state remains authoritative.

## Ownership transfer

If ownership must move from one state to another:

1. Freeze both mutation paths.
2. Verify the source state owns the resource and the destination does not.
3. Capture rollback evidence.
4. Remove ownership from the source state **without destroying the cloud resource**.
5. Import into the destination state.
6. Reconcile configuration and run a clean plan.
7. Keep the legacy execution path disabled until its code can no longer recreate or re-adopt the resource.

Never leave two independent states claiming the same physical resource.

## Teardown boundary

Destroy workload resources before touching the foundation. To remove a state bucket, first disable automation, preserve authoritative state and migrate state away from that bucket. Removing `prevent_destroy` or deleting a state bucket requires its own reviewed recovery procedure.
