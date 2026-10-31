"""SQLite persistence layer."""
import json
import os
import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


class IdempotencyConflictError(Exception):
    """An idempotency key was reused for a different event."""


def db_path() -> Path:
    return Path(os.environ.get("HOMELAB_DOCS_DB", "./data/homelab.sqlite3"))


def connect() -> sqlite3.Connection:
    path = db_path()
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    conn = sqlite3.connect(path)
    try:
        # Restrict the database file on POSIX. The service account should own the
        # parent directory; do not change permissions on an existing parent path.
        if os.name == "posix":
            os.chmod(path, 0o600)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA foreign_keys=ON")
        conn.execute("PRAGMA journal_mode=WAL")
        return conn
    except Exception:
        conn.close()
        raise


def init_db() -> None:
    with connect() as c:
        c.executescript("""
        CREATE TABLE IF NOT EXISTS events (
          id INTEGER PRIMARY KEY AUTOINCREMENT, host_id TEXT NOT NULL,
          client_event_id TEXT,
          event_type TEXT NOT NULL, timestamp TEXT NOT NULL, session_id TEXT,
          summary TEXT NOT NULL, payload TEXT NOT NULL, evidence_refs TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_events_host_time ON events(host_id, timestamp);
        CREATE TABLE IF NOT EXISTS snapshots (
          id INTEGER PRIMARY KEY AUTOINCREMENT, host_id TEXT NOT NULL,
          captured_at TEXT NOT NULL, source TEXT NOT NULL, state TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_snapshots_host_id ON snapshots(host_id, id);
        """)
        columns = {row["name"] for row in c.execute("PRAGMA table_info(events)").fetchall()}
        if "client_event_id" not in columns:
            c.execute("ALTER TABLE events ADD COLUMN client_event_id TEXT")

        # Older versions enforced global uniqueness. Replace that constraint with
        # host-scoped uniqueness so independent collectors cannot collide.
        c.execute("DROP INDEX IF EXISTS idx_events_client_event_id")
        c.execute(
            "CREATE UNIQUE INDEX IF NOT EXISTS idx_events_host_client_event_id "
            "ON events(host_id, client_event_id) WHERE client_event_id IS NOT NULL"
        )


def insert_event(event: dict[str, Any]) -> int:
    client_event_id = event.get("client_event_id")
    timestamp = event.get("timestamp") or datetime.now(timezone.utc).isoformat()
    payload_json = json.dumps(event.get("payload", {}), ensure_ascii=False, sort_keys=True)
    evidence_refs_json = json.dumps(event.get("evidence_refs", []), ensure_ascii=False)
    values = (
        client_event_id, event["host_id"], event["event_type"], timestamp,
        event.get("session_id"), event["summary"], payload_json, evidence_refs_json,
    )

    with connect() as c:
        try:
            cur = c.execute(
                "INSERT INTO events(client_event_id,host_id,event_type,timestamp,session_id,summary,payload,evidence_refs) "
                "VALUES(?,?,?,?,?,?,?,?)",
                values,
            )
            return int(cur.lastrowid)
        except sqlite3.IntegrityError:
            if not client_event_id:
                raise
            row = c.execute(
                "SELECT * FROM events WHERE host_id=? AND client_event_id=?",
                (event["host_id"], client_event_id),
            ).fetchone()
            if row is None:
                raise

            same_event = (
                row["event_type"] == event["event_type"]
                and (event.get("timestamp") is None or row["timestamp"] == timestamp)
                and row["session_id"] == event.get("session_id")
                and row["summary"] == event["summary"]
                and json.loads(row["payload"]) == json.loads(payload_json)
                and json.loads(row["evidence_refs"]) == json.loads(evidence_refs_json)
            )
            if same_event:
                return int(row["id"])
            raise IdempotencyConflictError(
                "client_event_id has already been used for a different event on this host"
            )


def list_events(host_id: str, limit: int = 100) -> list[dict[str, Any]]:
    with connect() as c:
        rows = c.execute(
            "SELECT * FROM events WHERE host_id=? ORDER BY timestamp DESC,id DESC LIMIT ?",
            (host_id, limit),
        ).fetchall()
    result = []
    for row in rows:
        item = dict(row)
        item["payload"] = json.loads(item["payload"])
        item["evidence_refs"] = json.loads(item["evidence_refs"])
        result.append(item)
    return result


def insert_snapshot(snapshot: dict[str, Any]) -> int:
    with connect() as c:
        cur = c.execute(
            "INSERT INTO snapshots(host_id,captured_at,source,state) VALUES(?,?,?,?)",
            (
                snapshot["host_id"], snapshot["captured_at"], snapshot["source"],
                json.dumps(snapshot["state"], sort_keys=True, ensure_ascii=False),
            ),
        )
        return int(cur.lastrowid)


def get_snapshot(snapshot_id: int) -> dict[str, Any] | None:
    with connect() as c:
        row = c.execute("SELECT * FROM snapshots WHERE id=?", (snapshot_id,)).fetchone()
    if row is None:
        return None
    item = dict(row)
    item["state"] = json.loads(item["state"])
    return item


def previous_snapshot(host_id: str, snapshot_id: int) -> dict[str, Any] | None:
    with connect() as c:
        row = c.execute(
            "SELECT * FROM snapshots WHERE host_id=? AND id<? ORDER BY id DESC LIMIT 1",
            (host_id, snapshot_id),
        ).fetchone()
    if row is None:
        return None
    item = dict(row)
    item["state"] = json.loads(item["state"])
    return item


def latest_snapshots(host_id: str, limit: int = 2) -> list[dict[str, Any]]:
    with connect() as c:
        rows = c.execute(
            "SELECT * FROM snapshots WHERE host_id=? ORDER BY id DESC LIMIT ?",
            (host_id, limit),
        ).fetchall()
    result = []
    for row in rows:
        item = dict(row)
        item["state"] = json.loads(item["state"])
        result.append(item)
    return result
