import argparse
import json
import tempfile
import unittest
from pathlib import Path

from scripts import worker_release


class WorkerReleaseTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        self.dockerfile = self.root / "Dockerfile"
        self.sbom = self.root / "sbom.json"
        self.provenance = self.root / "provenance.json"
        self.manifest = self.root / "worker-build-manifest.json"
        self.release = self.root / "worker-release.json"

        self.dockerfile.write_text("FROM scratch\n", encoding="utf-8")
        self.sbom.write_text(
            json.dumps(
                {
                    "SPDXID": "SPDXRef-DOCUMENT",
                    "name": "synthetic-worker",
                    "spdxVersion": "SPDX-2.3",
                },
                sort_keys=True,
                separators=(",", ":"),
            )
            + "\n",
            encoding="utf-8",
        )
        self.provenance.write_text(
            json.dumps(
                {
                    "buildType": (
                        "https://mobyproject.org/buildkit@v1"
                    ),
                    "builder": {
                        "id": "https://github.com/docker/build-push-action"
                    },
                },
                sort_keys=True,
                separators=(",", ":"),
            )
            + "\n",
            encoding="utf-8",
        )

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def create_args(self, output: Path | None = None) -> argparse.Namespace:
        return argparse.Namespace(
            output=str(output or self.manifest),
            repository=worker_release.EXPECTED_REPOSITORY,
            source_commit="a" * 40,
            source_workflow_ref=worker_release.EXPECTED_WORKFLOW_REF,
            source_run_id="123456",
            source_run_attempt="1",
            service_tree="b" * 40,
            dockerfile=str(self.dockerfile),
            image_uri=worker_release.EXPECTED_IMAGE_URI,
            image_digest=f"sha256:{'c' * 64}",
            platform=worker_release.EXPECTED_PLATFORM,
            sbom=str(self.sbom),
            provenance=str(self.provenance),
        )

    def test_manifest_and_release_are_deterministic_and_digest_bound(self) -> None:
        second_manifest = self.root / "second.json"
        worker_release.create_build_manifest(self.create_args())
        worker_release.create_build_manifest(self.create_args(second_manifest))
        self.assertEqual(
            self.manifest.read_bytes(),
            second_manifest.read_bytes(),
        )

        worker_release.verify_build_manifest(
            argparse.Namespace(
                manifest=str(self.manifest),
                expected_digest=f"sha256:{'c' * 64}",
                expected_source_commit="a" * 40,
                expected_run_id="123456",
                expected_run_attempt="1",
                expected_service_tree="b" * 40,
                expected_dockerfile_sha256=worker_release._sha256(
                    self.dockerfile
                ),
                sbom=str(self.sbom),
                provenance=str(self.provenance),
            )
        )
        worker_release.write_release(
            argparse.Namespace(
                manifest=str(self.manifest),
                output=str(self.release),
                expected_digest=f"sha256:{'c' * 64}",
            )
        )
        release = json.loads(self.release.read_text(encoding="utf-8"))
        worker_release.validate_release(release)
        self.assertEqual(release["evidence"], "buildkit-sbom-provenance")
        self.assertEqual(
            release["image_ref"],
            f"{worker_release.EXPECTED_IMAGE_URI}@sha256:{'c' * 64}",
        )

    def test_evidence_tampering_is_rejected(self) -> None:
        worker_release.create_build_manifest(self.create_args())
        self.sbom.write_text(
            self.sbom.read_text(encoding="utf-8") + " ",
            encoding="utf-8",
        )
        with self.assertRaisesRegex(ValueError, "SBOM SHA-256"):
            worker_release.verify_build_manifest(
                argparse.Namespace(
                    manifest=str(self.manifest),
                    expected_digest=f"sha256:{'c' * 64}",
                    expected_source_commit=None,
                    expected_run_id=None,
                    expected_run_attempt=None,
                    expected_service_tree=None,
                    expected_dockerfile_sha256=None,
                    sbom=str(self.sbom),
                    provenance=str(self.provenance),
                )
            )

    def test_slsa_v1_statement_is_accepted(self) -> None:
        self.provenance.write_text(
            json.dumps(
                {
                    "_type": "https://in-toto.io/Statement/v1",
                    "predicateType": "https://slsa.dev/provenance/v1",
                    "predicate": {
                        "buildDefinition": {
                            "buildType": (
                                "https://github.com/moby/buildkit/blob/master/"
                                "docs/attestations/slsa-definitions.md"
                            )
                        },
                        "runDetails": {
                            "builder": {"id": "buildkit"}
                        },
                    },
                    "subject": [],
                },
                sort_keys=True,
                separators=(",", ":"),
            )
            + "\n",
            encoding="utf-8",
        )
        worker_release.create_build_manifest(self.create_args())
        worker_release.verify_build_manifest(
            argparse.Namespace(
                manifest=str(self.manifest),
                expected_digest=f"sha256:{'c' * 64}",
                expected_source_commit="a" * 40,
                expected_run_id="123456",
                expected_run_attempt="1",
                expected_service_tree="b" * 40,
                expected_dockerfile_sha256=worker_release._sha256(
                    self.dockerfile
                ),
                sbom=str(self.sbom),
                provenance=str(self.provenance),
            )
        )

    def test_tag_or_mismatched_digest_is_rejected(self) -> None:
        worker_release.create_build_manifest(self.create_args())
        manifest = json.loads(self.manifest.read_text(encoding="utf-8"))
        manifest["image_ref"] = (
            f"{worker_release.EXPECTED_IMAGE_URI}:latest"
        )
        with self.assertRaisesRegex(ValueError, "image ref"):
            worker_release.validate_build_manifest(manifest)

        with self.assertRaisesRegex(ValueError, "image_digest"):
            worker_release.verify_build_manifest(
                argparse.Namespace(
                    manifest=str(self.manifest),
                    expected_digest=f"sha256:{'d' * 64}",
                    expected_source_commit=None,
                    expected_run_id=None,
                    expected_run_attempt=None,
                    expected_service_tree=None,
                    expected_dockerfile_sha256=None,
                    sbom=None,
                    provenance=None,
                )
            )

    def test_legacy_release_requires_null_evidence_fields(self) -> None:
        legacy = {
            "schema_version": 1,
            "repository": worker_release.EXPECTED_REPOSITORY,
            "source_commit": "e" * 40,
            "source_workflow_ref": worker_release.EXPECTED_WORKFLOW_REF,
            "source_run_id": "34162498643",
            "source_run_attempt": "1",
            "service_tree": None,
            "dockerfile_sha256": None,
            "image_digest": f"sha256:{'f' * 64}",
            "image_ref": (
                f"{worker_release.EXPECTED_IMAGE_URI}@sha256:{'f' * 64}"
            ),
            "sbom_sha256": None,
            "provenance_sha256": None,
            "build_manifest_sha256": None,
            "evidence": "legacy-summary-only",
        }
        worker_release.validate_release(legacy)
        legacy["sbom_sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "must be null"):
            worker_release.validate_release(legacy)


if __name__ == "__main__":
    unittest.main()
