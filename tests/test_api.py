from fastapi.testclient import TestClient
from homelab_docs.app import app


def test_health_is_public():
    client = TestClient(app)
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["service"] == "documentor"


def test_protected_route_fails_closed_without_token(monkeypatch):
    monkeypatch.delenv("HOMELAB_DOCS_API_TOKEN", raising=False)
    client = TestClient(app)
    response = client.get("/api/v1/events", params={"host_id": "test"})
    assert response.status_code == 503
