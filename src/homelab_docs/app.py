"""Documentor API. Never executes commands received from collectors."""
import hmac
import os
from datetime import datetime, timezone
from fastapi import Depends, FastAPI, Header, HTTPException, Query
from fastapi.responses import PlainTextResponse
from . import db
from .diffing import diff_values
from .reports import render_report
from .schemas import EventIn, SnapshotIn

app = FastAPI(title="Documentor Homelab API", version="0.1.0")


@app.on_event("startup")
def startup() -> None:
    db.init_db()


def require_token(authorization: str | None = Header(default=None)) -> None:
    expected = os.environ.get("HOMELAB_DOCS_API_TOKEN", "")
    if not expected:
        raise HTTPException(status_code=503, detail="API token is not configured")
    supplied = authorization.removeprefix("Bearer ") if authorization else ""
    if not hmac.compare_digest(supplied, expected):
        raise HTTPException(status_code=401, detail="Invalid bearer token")


@app.get("/health")
def health():
    return {"status": "ok", "service": "documentor", "version": "0.1.0"}


@app.post("/api/v1/events", dependencies=[Depends(require_token)])
def post_event(event: EventIn):
    data = event.model_dump()
    data["timestamp"] = data["timestamp"] or datetime.now(timezone.utc).isoformat()
    event_id = db.insert_event(data)
    return {"id": event_id, "stored": True}


@app.get("/api/v1/events", dependencies=[Depends(require_token)])
def get_events(host_id: str, limit: int = Query(default=100, ge=1, le=1000)):
    return {"events": db.list_events(host_id, limit)}


@app.post("/api/v1/snapshots", dependencies=[Depends(require_token)])
def post_snapshot(snapshot: SnapshotIn):
    data = snapshot.model_dump()
    data["captured_at"] = data["captured_at"] or datetime.now(timezone.utc).isoformat()
    snapshot_id = db.insert_snapshot(data)
    return {"id": snapshot_id, "stored": True}


@app.get("/api/v1/snapshots/{snapshot_id}/diff", dependencies=[Depends(require_token)])
def snapshot_diff(snapshot_id: int):
    current = db.get_snapshot(snapshot_id)
    if not current:
        raise HTTPException(status_code=404, detail="Snapshot not found")
    earlier = [s for s in db.latest_snapshots(current["host_id"], 1000) if s["id"] < snapshot_id]
    if not earlier:
        return {"host_id": current["host_id"], "snapshot_id": snapshot_id, "baseline": None, "diff": []}
    baseline = earlier[0]
    return {"host_id": current["host_id"], "snapshot_id": snapshot_id, "baseline": baseline["id"], "diff": diff_values(baseline["state"], current["state"])}


@app.post("/api/v1/reports/{host_id}", response_class=PlainTextResponse, dependencies=[Depends(require_token)])
def report(host_id: str):
    events = db.list_events(host_id, 1000)
    snapshots = db.latest_snapshots(host_id, 2)
    diffs = diff_values(snapshots[1]["state"], snapshots[0]["state"]) if len(snapshots) == 2 else []
    return render_report(host_id, events, diffs)
