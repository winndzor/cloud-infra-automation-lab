# Assumptions and Evidence

This file separates verified lab behavior from assumptions so documentation does not silently turn inference into fact.

| Statement | Classification | Consequence |
| --- | --- | --- |
| The lab runs only in a personal GCP sandbox using synthetic data. | Confirmed | No production/customer data is required. |
| Billing is enabled for the sandbox. | Confirmed | Every deployed service needs explicit cost controls. |
| Budget alerts are notification controls, not spending caps. | Confirmed | Scale limits, retention and service selection remain the enforceable cost boundary. |
| GitHub Actions, WIF, exact-plan apply, isolated state and immutable action references are active in the lab design. | Confirmed | Preserve these controls while expanding the workload. |
| The guarded input bucket and event-delivery path were deployed through the exact-plan workflow and verified with zero drift in the source lab. | Confirmed | Future changes should preserve state ownership and the deployment boundary. |
| A synthetic object produced a metadata-only BigQuery row and matching structured Cloud Run log through authenticated Pub/Sub push. | Confirmed | The smoke-test runbook can repeat the proof without real data. |
| GitHub Free provides the same governance controls as an enterprise repository. | Confirmed false | The lab documents a self-operated manual handoff and does not claim independent approval. |
| A resource visible in GCP is safe to import into this Terraform state. | Confirmed false | Existing state ownership must be verified before any import. |

## Update rule

Every important design claim should remain marked as confirmed, proposed, inferred or unknown. New evidence changes the classification; it does not silently rewrite history.
## Public portfolio copy

Deployment-specific GCP identifiers in this repository are intentionally replaced with non-production example values. The checked-in `worker-release.json` is a synthetic contract fixture used to exercise digest-only validation; it is not presented as proof of a publicly reachable image or historical GitHub Actions run.

