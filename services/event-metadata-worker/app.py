import base64
import binascii
import json
import os
from datetime import datetime, timezone
from typing import Any

from flask import Flask, Response, request
from google.cloud import bigquery, secretmanager


def _structured_log(severity: str, message: str, **fields: Any) -> None:
    print(
        json.dumps(
            {"severity": severity, "message": message, **fields},
            sort_keys=True,
        ),
        flush=True,
    )


def _decode_storage_event(envelope: dict[str, Any]) -> tuple[dict[str, Any], str]:
    message = envelope.get("message")
    if not isinstance(message, dict):
        raise ValueError("missing Pub/Sub message")

    encoded_data = message.get("data")
    message_id = message.get("messageId")
    if not isinstance(encoded_data, str) or not isinstance(message_id, str):
        raise ValueError("missing Pub/Sub data or messageId")

    try:
        decoded = base64.b64decode(encoded_data, validate=True)
        event = json.loads(decoded)
    except (binascii.Error, json.JSONDecodeError) as error:
        raise ValueError("invalid storage event payload") from error

    if not isinstance(event, dict):
        raise ValueError("storage event must be a JSON object")

    bucket = event.get("bucket")
    object_name = event.get("name")
    if not isinstance(bucket, str) or not isinstance(object_name, str):
        raise ValueError("storage event is missing bucket or object name")

    return event, message_id


def create_app(
    client: Any | None = None,
    config_client: Any | None = None,
) -> Flask:
    app = Flask(__name__)
    bigquery_client = client
    secret_client = config_client

    @app.get("/health")
    def health() -> dict[str, str]:
        return {"status": "ok"}

    @app.post("/")
    def process_event() -> Response:
        nonlocal bigquery_client, secret_client

        envelope = request.get_json(silent=True)
        if not isinstance(envelope, dict):
            _structured_log("WARNING", "discarded non-JSON Pub/Sub request")
            return Response(status=204)

        try:
            event, message_id = _decode_storage_event(envelope)
        except ValueError as error:
            _structured_log("WARNING", "discarded invalid storage event", reason=str(error))
            return Response(status=204)

        expected_bucket = os.environ["EXPECTED_BUCKET"]
        if event["bucket"] != expected_bucket:
            _structured_log(
                "WARNING",
                "discarded event outside the synthetic input boundary",
                event_id=message_id,
                bucket=event["bucket"],
            )
            return Response(status=204)

        table_id = os.environ["BIGQUERY_TABLE"]
        try:
            secret_version = os.environ["PROCESSING_CONFIG_SECRET_VERSION"]
            if secret_client is None:
                secret_client = secretmanager.SecretManagerServiceClient()
            secret_response = secret_client.access_secret_version(
                request={"name": secret_version}
            )
            processing_config = json.loads(secret_response.payload.data.decode("utf-8"))
        except Exception:
            _structured_log("ERROR", "synthetic processing configuration is invalid")
            return Response(status=500)

        if (
            not isinstance(processing_config, dict)
            or processing_config.get("mode") != "metadata-only"
        ):
            _structured_log("ERROR", "synthetic processing mode is not allowed")
            return Response(status=500)

        if bigquery_client is None:
            bigquery_client = bigquery.Client()

        row = {
            "event_id": message_id,
            "bucket": event["bucket"],
            "object_name": event["name"],
            "object_generation": str(event.get("generation", "")),
            "object_size": int(event.get("size", 0)),
            "event_time": event.get("timeCreated"),
            "processed_at": datetime.now(timezone.utc).isoformat(),
        }

        errors = bigquery_client.insert_rows_json(
            table_id,
            [row],
            row_ids=[message_id],
        )
        if errors:
            _structured_log(
                "ERROR",
                "BigQuery insert failed",
                event_id=message_id,
                error_count=len(errors),
            )
            return Response(status=500)

        _structured_log(
            "INFO",
            "synthetic storage event processed",
            event_id=message_id,
            bucket=event["bucket"],
            object_name=event["name"],
        )
        return Response(status=204)

    return app


app = create_app()
