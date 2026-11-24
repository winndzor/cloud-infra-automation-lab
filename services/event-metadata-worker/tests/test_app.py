import base64
import json
from types import SimpleNamespace

import pytest

from app import create_app


class FakeBigQueryClient:
    def __init__(self, errors=None):
        self.errors = errors or []
        self.calls = []

    def insert_rows_json(self, table_id, rows, row_ids):
        self.calls.append(
            {
                "table_id": table_id,
                "rows": rows,
                "row_ids": row_ids,
            }
        )
        return self.errors


class FakeSecretManagerClient:
    def __init__(self, config=None):
        self.config = config or {
            "mode": "metadata-only",
            "marker": "do-not-log-or-store",
        }
        self.requests = []

    def access_secret_version(self, request):
        self.requests.append(request)
        return SimpleNamespace(
            payload=SimpleNamespace(data=json.dumps(self.config).encode())
        )


@pytest.fixture(autouse=True)
def worker_environment(monkeypatch):
    monkeypatch.setenv(
        "EXPECTED_BUCKET",
        "example-cloud-infra-lab-123456789012-input",
    )
    monkeypatch.setenv(
        "BIGQUERY_TABLE",
        "example-gcp-project.cloud_infra_lab.events",
    )
    monkeypatch.setenv(
        "PROCESSING_CONFIG_SECRET_VERSION",
        "projects/example-gcp-project/secrets/cloud-infra-lab-worker-config/versions/latest",
    )


def pubsub_envelope(event, message_id="message-1"):
    return {
        "message": {
            "data": base64.b64encode(json.dumps(event).encode()).decode(),
            "messageId": message_id,
        }
    }


def valid_storage_event():
    return {
        "bucket": "example-cloud-infra-lab-123456789012-input",
        "name": "fixtures/event.json",
        "generation": "12345",
        "size": "42",
        "timeCreated": "2026-09-07T20:00:00Z",
    }


def test_health_endpoint():
    app = create_app(FakeBigQueryClient(), FakeSecretManagerClient())

    response = app.test_client().get("/health")

    assert response.status_code == 200
    assert response.get_json() == {"status": "ok"}


def test_valid_event_inserts_metadata_only(capsys):
    client = FakeBigQueryClient()
    config_client = FakeSecretManagerClient()
    app = create_app(client, config_client)

    response = app.test_client().post("/", json=pubsub_envelope(valid_storage_event()))

    assert response.status_code == 204
    assert len(client.calls) == 1
    call = client.calls[0]
    assert call["table_id"] == "example-gcp-project.cloud_infra_lab.events"
    assert call["row_ids"] == ["message-1"]
    assert call["rows"][0]["object_name"] == "fixtures/event.json"
    assert "marker" not in call["rows"][0]
    assert "processing_config" not in call["rows"][0]
    assert "data" not in call["rows"][0]
    assert "do-not-log-or-store" not in capsys.readouterr().out
    assert config_client.requests == [
        {
            "name": (
                "projects/example-gcp-project/secrets/"
                "cloud-infra-lab-worker-config/versions/latest"
            )
        }
    ]


def test_invalid_payload_is_acknowledged_without_insert():
    client = FakeBigQueryClient()
    app = create_app(client, FakeSecretManagerClient())

    response = app.test_client().post(
        "/",
        json={"message": {"messageId": "bad", "data": "not-base64"}},
    )

    assert response.status_code == 204
    assert client.calls == []


def test_event_from_another_bucket_is_acknowledged_without_insert():
    client = FakeBigQueryClient()
    app = create_app(client, FakeSecretManagerClient())
    event = valid_storage_event()
    event["bucket"] = "not-the-lab-input"

    response = app.test_client().post("/", json=pubsub_envelope(event))

    assert response.status_code == 204
    assert client.calls == []


def test_bigquery_error_requests_pubsub_retry():
    client = FakeBigQueryClient(errors=[{"reason": "backendError"}])
    app = create_app(client, FakeSecretManagerClient())

    response = app.test_client().post("/", json=pubsub_envelope(valid_storage_event()))

    assert response.status_code == 500


def test_invalid_processing_config_requests_pubsub_retry():
    client = FakeBigQueryClient()
    config_client = FakeSecretManagerClient(config={"mode": "content-copy"})
    app = create_app(client, config_client)

    response = app.test_client().post("/", json=pubsub_envelope(valid_storage_event()))

    assert response.status_code == 500
    assert client.calls == []
