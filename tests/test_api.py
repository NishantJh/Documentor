import pytest
from fastapi.testclient import TestClient

from homelab_docs.app import app


@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setenv("HOMELAB_DOCS_API_TOKEN", "test-token-that-is-long-enough-for-tests")
    monkeypatch.setenv("HOMELAB_DOCS_DB", str(tmp_path / "homelab.sqlite3"))
    with TestClient(app) as test_client:
        yield test_client


def auth():
    return {"Authorization": "Bearer test-token-that-is-long-enough-for-tests"}


def test_health_is_public(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["service"] == "documentor"


def test_protected_route_fails_closed_without_token(client, monkeypatch):
    monkeypatch.delenv("HOMELAB_DOCS_API_TOKEN", raising=False)
    response = client.get("/api/v1/events", params={"host_id": "test"})
    assert response.status_code == 503


def test_protected_route_rejects_invalid_token(client):
    response = client.get(
        "/api/v1/events",
        params={"host_id": "test"},
        headers={"Authorization": "Bearer wrong-token"},
    )
    assert response.status_code == 401


def test_event_round_trip(client):
    created = client.post(
        "/api/v1/events",
        headers=auth(),
        json={
            "host_id": "synthetic-host",
            "event_type": "command",
            "summary": "Synthetic test event",
            "payload": {"exit_code": 0},
            "evidence_refs": ["synthetic://event/1"],
        },
    )
    assert created.status_code == 200
    assert created.json()["stored"] is True

    response = client.get(
        "/api/v1/events",
        params={"host_id": "synthetic-host"},
        headers=auth(),
    )
    assert response.status_code == 200
    event = response.json()["events"][0]
    assert event["summary"] == "Synthetic test event"
    assert event["payload"] == {"exit_code": 0}
    assert event["evidence_refs"] == ["synthetic://event/1"]
    assert event["timestamp"]


def test_snapshot_diff_and_report(client):
    headers = auth()
    first = client.post(
        "/api/v1/snapshots",
        headers=headers,
        json={
            "host_id": "synthetic-host",
            "source": "test",
            "state": {"network": {"dns": "1.1.1.1"}},
        },
    )
    second = client.post(
        "/api/v1/snapshots",
        headers=headers,
        json={
            "host_id": "synthetic-host",
            "source": "test",
            "state": {"network": {"dns": "9.9.9.9"}},
        },
    )
    assert first.status_code == second.status_code == 200

    diff = client.get(
        f"/api/v1/snapshots/{second.json()['id']}/diff",
        headers=headers,
    )
    assert diff.status_code == 200
    assert diff.json()["baseline"] == first.json()["id"]
    assert diff.json()["diff"] == [
        {"path": "$.network.dns", "change": "changed", "before": "1.1.1.1", "after": "9.9.9.9"}
    ]

    report = client.post("/api/v1/reports/synthetic-host", headers=headers)
    assert report.status_code == 200
    assert "Latest configuration differences" in report.text
    assert "$.network.dns" in report.text
    assert "Not yet generated" in report.text


def test_missing_snapshot_returns_404(client):
    response = client.get("/api/v1/snapshots/9999/diff", headers=auth())
    assert response.status_code == 404


def test_rejects_oversized_event_payload(client):
    response = client.post(
        "/api/v1/events",
        headers=auth(),
        json={
            "host_id": "synthetic-host",
            "event_type": "command",
            "summary": "oversized synthetic payload",
            "payload": {"output": "x" * (256 * 1024 + 1)},
        },
    )
    assert response.status_code == 422


def test_rejects_unknown_event_fields(client):
    response = client.post(
        "/api/v1/events",
        headers=auth(),
        json={
            "host_id": "synthetic-host",
            "event_type": "command",
            "summary": "unexpected field",
            "unreviewed": "must not be silently accepted",
        },
    )
    assert response.status_code == 422


def test_bearer_scheme_is_case_insensitive(client):
    response = client.get(
        "/api/v1/events",
        params={"host_id": "synthetic-host"},
        headers={"Authorization": "bEaReR test-token-that-is-long-enough-for-tests"},
    )
    assert response.status_code == 200


def test_report_renders_untrusted_summary_as_single_line(client):
    response = client.post(
        "/api/v1/events",
        headers=auth(),
        json={
            "host_id": "synthetic-host",
            "event_type": "command",
            "summary": "safe title" + chr(10) + "## injected heading",
        },
    )
    assert response.status_code == 200
    report = client.post("/api/v1/reports/synthetic-host", headers=auth())
    assert report.status_code == 200
    assert "\n## injected heading" not in report.text
    assert "safe title ## injected heading" in report.text


def test_database_file_has_restricted_posix_permissions(client, tmp_path):
    import os
    import stat

    if os.name != "posix":
        pytest.skip("POSIX file permissions are not available on this platform")
    db_file = tmp_path / "homelab.sqlite3"
    assert db_file.exists()
    assert stat.S_IMODE(db_file.stat().st_mode) == 0o600


def test_retries_with_same_client_event_id_are_idempotent(client):
    event = {
        "client_event_id": "recorder-event-0001",
        "host_id": "synthetic-host",
        "event_type": "powershell_command",
        "summary": "Synthetic retried command",
        "payload": {"powershell_success": True},
    }
    first = client.post("/api/v1/events", headers=auth(), json=event)
    second = client.post("/api/v1/events", headers=auth(), json=event)
    assert first.status_code == second.status_code == 200
    assert first.json()["id"] == second.json()["id"]

    response = client.get(
        "/api/v1/events",
        params={"host_id": "synthetic-host"},
        headers=auth(),
    )
    assert response.status_code == 200
    assert len(response.json()["events"]) == 1


def test_rejects_naive_event_timestamp(client):
    response = client.post(
        "/api/v1/events",
        headers=auth(),
        json={
            "host_id": "synthetic-host",
            "event_type": "command",
            "summary": "naive timestamp",
            "timestamp": "2026-10-29T12:00:00",
        },
    )
    assert response.status_code == 422
