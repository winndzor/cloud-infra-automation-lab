# Manual Plan and Apply Runbook

## Scope

This runbook deploys the synthetic `environments/lab` root through the
repository's short-lived GitHub WIF identities. It does not authorize local
apply or changes to the human-owned foundation.

GitHub Free does not provide an independent approval gate for this private
repository. The process below is a self-operated owner confirmation.

## Preconditions

1. The intended configuration is merged to `main`.
2. The validation workflow for that commit is successful.
3. The owner account, numeric actor ID `38678897`, dispatches both workflows.
4. No other lab plan or apply run is active.

## Create and review a plan

Dispatch **Terraform lab plan** from `main`, or run:

```shell
gh workflow run terraform-plan.yml --ref main
```

Open the completed run summary and review the rendered plan. Confirm:

- the source commit is the intended current `main` commit;
- only intended resources owned by `environments/lab` change;
- there are no unexpected replacements or destroys;
- there are no cross-project references or changes to resources owned by another state;
- the run completed successfully.

Copy the source run ID and saved-plan SHA-256 from the summary. Do not substitute
the GitHub artifact digest; the apply input is the digest of `lab.tfplan`.

## Apply the exact reviewed plan

Dispatch **Terraform lab apply** from `main` with the copied values, or run:

```shell
gh workflow run terraform-apply.yml \
  --ref main \
  -f source_run_id=PLAN_RUN_ID \
  -f plan_sha256=PLAN_SHA256
```

Before it obtains a Google token, the workflow verifies:

- both dispatches were made by the repository owner;
- the source was a successful plan workflow run on `main`;
- the source commit still equals the apply run's current `main` commit;
- the expected one-day artifact and its three files are present;
- the manifest binds the repository, commit, workflow, run, attempt, artifact,
  saved plan, rendered plan, and their SHA-256 values;
- the operator-supplied digest matches the downloaded binary plan.

The apply identity then initializes the canonical backend, independently renders
the saved plan, compares that rendering with the reviewed text, applies the
binary plan, and runs a zero-drift check.

## Stop conditions

- If `main` advances, discard the old handoff and create a new plan.
- If the artifact expires, create a new plan. Do not recreate or re-upload it.
- If any source-run, manifest, digest, or rendering check fails, do not bypass
  it. Diagnose the mismatch and re-plan.
- If apply succeeds but the zero-drift check fails, preserve both run logs and
  investigate before another dispatch.
- Never copy the saved plan into the repository or apply it locally.
