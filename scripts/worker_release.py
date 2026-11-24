#!/usr/bin/env python3
"""Create and verify immutable synthetic-worker build and release records."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

EXPECTED_REPOSITORY = "winndzor/cloud-infra-automation-lab"
EXPECTED_WORKFLOW_REF = (
    "winndzor/cloud-infra-automation-lab/.github/workflows/container-build.yml@refs/heads/main"
)
EXPECTED_IMAGE_URI = (
    "europe-central2-docker.pkg.dev/example-gcp-project/"
    "cloud-infra-lab/event-metadata-worker"
)
EXPECTED_PLATFORM = "linux/amd64"

SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")
DIGEST_PATTERN = re.compile(r"^sha256:[0-9a-f]{64}$")
GIT_OBJECT_PATTERN = re.compile(r"^[0-9a-f]{40}(?:[0-9a-f]{24})?$")
RUN_ID_PATTERN = re.compile(r"^[1-9][0-9]*$")

BUILD_MANIFEST_KEYS = {
    "dockerfile_sha256",
    "image_digest",
    "image_ref",
    "image_uri",
    "platform",
    "provenance_sha256",
    "repository",
    "sbom_sha256",
    "schema_version",
    "service_tree",
    "source_commit",
    "source_run_attempt",
    "source_run_id",
    "source_workflow_ref",
}

RELEASE_KEYS = {
    "build_manifest_sha256",
    "dockerfile_sha256",
    "evidence",
    "image_digest",
    "image_ref",
    "provenance_sha256",
    "repository",
    "sbom_sha256",
    "schema_version",
    "service_tree",
    "source_commit",
    "source_run_attempt",
    "source_run_id",
    "source_workflow_ref",
}


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def _read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"{path} is not valid readable JSON") from error
    _require(isinstance(value, dict), f"{path} must contain one JSON object")
    return value


def _sha256(path: Path) -> str:
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()
    except OSError as error:
        raise ValueError(f"cannot read {path} for SHA-256") from error


def _write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def validate_sbom(path: Path) -> None:
    sbom = _read_json(path)
    _require(sbom.get("SPDXID") == "SPDXRef-DOCUMENT", "SBOM must be an SPDX document")
    _require(
        isinstance(sbom.get("spdxVersion"), str)
        and sbom["spdxVersion"].startswith("SPDX-"),
        "SBOM must declare an SPDX version",
    )


def validate_provenance(path: Path) -> None:
    provenance = _read_json(path)
    candidates = [provenance]
    if isinstance(provenance.get("predicate"), dict):
        candidates.append(provenance["predicate"])

    def is_buildkit_type(value: Any) -> bool:
        return isinstance(value, str) and (
            value.startswith("https://mobyproject.org/buildkit@")
            or value
            == (
                "https://github.com/moby/buildkit/blob/master/"
                "docs/attestations/slsa-definitions.md"
            )
        )

    def is_buildkit_v02(candidate: dict[str, Any]) -> bool:
        return (
            is_buildkit_type(candidate.get("buildType"))
            and isinstance(candidate.get("builder"), dict)
        )

    def is_buildkit_v1(candidate: dict[str, Any]) -> bool:
        build_definition = candidate.get("buildDefinition")
        run_details = candidate.get("runDetails")
        return (
            isinstance(build_definition, dict)
            and is_buildkit_type(build_definition.get("buildType"))
            and isinstance(run_details, dict)
            and isinstance(run_details.get("builder"), dict)
        )

    _require(
        any(
            is_buildkit_v02(candidate) or is_buildkit_v1(candidate)
            for candidate in candidates
        ),
        "provenance must identify BuildKit and its builder",
    )


def validate_build_manifest(manifest: dict[str, Any]) -> None:
    _require(
        set(manifest) == BUILD_MANIFEST_KEYS,
        "build manifest has missing or unexpected fields",
    )
    _require(manifest["schema_version"] == 1, "unsupported build manifest schema")
    _require(
        manifest["repository"] == EXPECTED_REPOSITORY,
        "build manifest repository is outside the lab boundary",
    )
    _require(
        manifest["source_workflow_ref"] == EXPECTED_WORKFLOW_REF,
        "build manifest workflow ref is not trusted",
    )
    _require(
        isinstance(manifest["source_commit"], str)
        and GIT_OBJECT_PATTERN.fullmatch(manifest["source_commit"]) is not None,
        "source commit must be a full Git object ID",
    )
    _require(
        isinstance(manifest["service_tree"], str)
        and GIT_OBJECT_PATTERN.fullmatch(manifest["service_tree"]) is not None,
        "service tree must be a full Git object ID",
    )
    _require(
        isinstance(manifest["source_run_id"], str)
        and RUN_ID_PATTERN.fullmatch(manifest["source_run_id"]) is not None,
        "source run ID must be a positive integer string",
    )
    _require(
        isinstance(manifest["source_run_attempt"], str)
        and RUN_ID_PATTERN.fullmatch(manifest["source_run_attempt"]) is not None,
        "source run attempt must be a positive integer string",
    )
    _require(
        manifest["image_uri"] == EXPECTED_IMAGE_URI,
        "image URI is outside the lab repository",
    )
    _require(
        isinstance(manifest["image_digest"], str)
        and DIGEST_PATTERN.fullmatch(manifest["image_digest"]) is not None,
        "image digest must be sha256 followed by 64 lowercase hex characters",
    )
    _require(
        manifest["image_ref"]
        == f"{manifest['image_uri']}@{manifest['image_digest']}",
        "image ref must combine the trusted URI and exact digest",
    )
    _require(
        manifest["platform"] == EXPECTED_PLATFORM,
        "only the linux/amd64 promotion platform is allowed",
    )
    for field in (
        "dockerfile_sha256",
        "sbom_sha256",
        "provenance_sha256",
    ):
        _require(
            isinstance(manifest[field], str)
            and SHA256_PATTERN.fullmatch(manifest[field]) is not None,
            f"{field} must contain a lowercase SHA-256",
        )


def create_build_manifest(args: argparse.Namespace) -> None:
    sbom_path = Path(args.sbom)
    provenance_path = Path(args.provenance)
    dockerfile_path = Path(args.dockerfile)
    validate_sbom(sbom_path)
    validate_provenance(provenance_path)

    manifest = {
        "schema_version": 1,
        "repository": args.repository,
        "source_commit": args.source_commit,
        "source_workflow_ref": args.source_workflow_ref,
        "source_run_id": args.source_run_id,
        "source_run_attempt": args.source_run_attempt,
        "service_tree": args.service_tree,
        "dockerfile_sha256": _sha256(dockerfile_path),
        "image_uri": args.image_uri,
        "image_digest": args.image_digest,
        "image_ref": f"{args.image_uri}@{args.image_digest}",
        "platform": args.platform,
        "sbom_sha256": _sha256(sbom_path),
        "provenance_sha256": _sha256(provenance_path),
    }
    validate_build_manifest(manifest)
    _write_json(Path(args.output), manifest)


def verify_build_manifest(args: argparse.Namespace) -> None:
    manifest = _read_json(Path(args.manifest))
    validate_build_manifest(manifest)

    expected_values = {
        "image_digest": args.expected_digest,
        "service_tree": args.expected_service_tree,
        "source_commit": args.expected_source_commit,
        "source_run_id": args.expected_run_id,
        "source_run_attempt": args.expected_run_attempt,
        "dockerfile_sha256": args.expected_dockerfile_sha256,
    }
    for field, expected in expected_values.items():
        if expected is not None:
            _require(manifest[field] == expected, f"{field} does not match trusted input")

    if args.sbom is not None or args.provenance is not None:
        _require(
            args.sbom is not None and args.provenance is not None,
            "SBOM and provenance must be verified together",
        )
        sbom_path = Path(args.sbom)
        provenance_path = Path(args.provenance)
        validate_sbom(sbom_path)
        validate_provenance(provenance_path)
        _require(
            _sha256(sbom_path) == manifest["sbom_sha256"],
            "SBOM SHA-256 does not match the build manifest",
        )
        _require(
            _sha256(provenance_path) == manifest["provenance_sha256"],
            "provenance SHA-256 does not match the build manifest",
        )


def validate_release(release: dict[str, Any]) -> None:
    _require(
        set(release) == RELEASE_KEYS,
        "worker release has missing or unexpected fields",
    )
    _require(release["schema_version"] == 1, "unsupported worker release schema")
    _require(
        release["repository"] == EXPECTED_REPOSITORY,
        "worker release repository is outside the lab boundary",
    )
    _require(
        release["source_workflow_ref"] == EXPECTED_WORKFLOW_REF,
        "worker release workflow ref is not trusted",
    )
    _require(
        isinstance(release["source_commit"], str)
        and GIT_OBJECT_PATTERN.fullmatch(release["source_commit"]) is not None,
        "worker release source commit is invalid",
    )
    _require(
        isinstance(release["source_run_id"], str)
        and RUN_ID_PATTERN.fullmatch(release["source_run_id"]) is not None,
        "worker release source run ID is invalid",
    )
    _require(
        isinstance(release["source_run_attempt"], str)
        and RUN_ID_PATTERN.fullmatch(release["source_run_attempt"]) is not None,
        "worker release source run attempt is invalid",
    )
    _require(
        isinstance(release["image_digest"], str)
        and DIGEST_PATTERN.fullmatch(release["image_digest"]) is not None,
        "worker release digest is invalid",
    )
    _require(
        release["image_ref"] == f"{EXPECTED_IMAGE_URI}@{release['image_digest']}",
        "worker release image ref is not the exact trusted digest",
    )

    if release["evidence"] == "legacy-summary-only":
        for field in (
            "build_manifest_sha256",
            "dockerfile_sha256",
            "provenance_sha256",
            "sbom_sha256",
            "service_tree",
        ):
            _require(release[field] is None, f"legacy release {field} must be null")
        return

    _require(
        release["evidence"] == "buildkit-sbom-provenance",
        "worker release evidence level is invalid",
    )
    _require(
        isinstance(release["service_tree"], str)
        and GIT_OBJECT_PATTERN.fullmatch(release["service_tree"]) is not None,
        "worker release service tree is invalid",
    )
    for field in (
        "build_manifest_sha256",
        "dockerfile_sha256",
        "provenance_sha256",
        "sbom_sha256",
    ):
        _require(
            isinstance(release[field], str)
            and SHA256_PATTERN.fullmatch(release[field]) is not None,
            f"worker release {field} is invalid",
        )


def write_release(args: argparse.Namespace) -> None:
    manifest_path = Path(args.manifest)
    manifest = _read_json(manifest_path)
    validate_build_manifest(manifest)
    if args.expected_digest is not None:
        _require(
            manifest["image_digest"] == args.expected_digest,
            "promotion digest does not match the build manifest",
        )

    release = {
        "schema_version": 1,
        "repository": manifest["repository"],
        "source_commit": manifest["source_commit"],
        "source_workflow_ref": manifest["source_workflow_ref"],
        "source_run_id": manifest["source_run_id"],
        "source_run_attempt": manifest["source_run_attempt"],
        "service_tree": manifest["service_tree"],
        "dockerfile_sha256": manifest["dockerfile_sha256"],
        "image_digest": manifest["image_digest"],
        "image_ref": manifest["image_ref"],
        "sbom_sha256": manifest["sbom_sha256"],
        "provenance_sha256": manifest["provenance_sha256"],
        "build_manifest_sha256": _sha256(manifest_path),
        "evidence": "buildkit-sbom-provenance",
    }
    validate_release(release)
    _write_json(Path(args.output), release)


def verify_release(args: argparse.Namespace) -> None:
    validate_release(_read_json(Path(args.release)))


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)

    create = commands.add_parser("create-build-manifest")
    create.add_argument("--output", required=True)
    create.add_argument("--repository", required=True)
    create.add_argument("--source-commit", required=True)
    create.add_argument("--source-workflow-ref", required=True)
    create.add_argument("--source-run-id", required=True)
    create.add_argument("--source-run-attempt", required=True)
    create.add_argument("--service-tree", required=True)
    create.add_argument("--dockerfile", required=True)
    create.add_argument("--image-uri", required=True)
    create.add_argument("--image-digest", required=True)
    create.add_argument("--platform", required=True)
    create.add_argument("--sbom", required=True)
    create.add_argument("--provenance", required=True)
    create.set_defaults(handler=create_build_manifest)

    verify = commands.add_parser("verify-build-manifest")
    verify.add_argument("--manifest", required=True)
    verify.add_argument("--expected-digest")
    verify.add_argument("--expected-source-commit")
    verify.add_argument("--expected-run-id")
    verify.add_argument("--expected-run-attempt")
    verify.add_argument("--expected-service-tree")
    verify.add_argument("--expected-dockerfile-sha256")
    verify.add_argument("--sbom")
    verify.add_argument("--provenance")
    verify.set_defaults(handler=verify_build_manifest)

    release = commands.add_parser("write-release")
    release.add_argument("--manifest", required=True)
    release.add_argument("--output", required=True)
    release.add_argument("--expected-digest")
    release.set_defaults(handler=write_release)

    verify_record = commands.add_parser("verify-release")
    verify_record.add_argument("--release", required=True)
    verify_record.set_defaults(handler=verify_release)

    return parser


def main() -> int:
    args = _build_parser().parse_args()
    try:
        args.handler(args)
    except ValueError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
