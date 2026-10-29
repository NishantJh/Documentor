"""SQLite persistence layer."""
import json
import os
import sqlite3
from pathlib import Path
from typing import Any


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


def insert_event(event: dict[str, Any]) -> int:
    with connect() as c:
        cur = c.execute(
            "INSERT INTO events(host_id,event_type,timestamp,session_id,summary,payload,evidence_refs) VALUES(?,?,?,?,?,?,?)",
            (
                event["host_id"], event["event_type"], event["timestamp"], event.get("session_id"),
                event["summary"], json.dumps(event.get("payload", {}), ensure_ascii=False),
                json.dumps(event.get("evidence_refs", []), ensure_ascii=False),
            ),
        )
        return int(cur.lastrowid)


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


def _snapshot_from_row(row: sqlite3.Row | None) -> dict[str, Any] | None:
    if row is None:
        return None
    item = dict(row)
    item["state"] = json.loads(item["state"])
    return item


def get_snapshot(snapshot_id: int) -> dict[str, Any] | None:
    with connect() as c:
        row = c.execute("SELECT * FROM snapshots WHERE id=?", (snapshot_id,)).fetchone()
    return _snapshot_from_row(row)


def previous_snapshot(host_id: str, snapshot_id: int) -> dict[str, Any] | None:
    """Return the nearest earlier inserted snapshot for this host."""
    with connect() as c:
        row = c.execute(
            "SELECT * FROM snapshots WHERE host_id=? AND id<? ORDER BY id DESC LIMIT 1",
            (host_id, snapshot_id),
        ).fetchone()
    return _snapshot_from_row(row)


def latest_snapshots(host_id: str, limit: int = 2) -> list[dict[str, Any]]:
    with connect() as c:
        rows = c.execute(
            "SELECT * FROM snapshots WHERE host_id=? ORDER BY id DESC LIMIT ?",
            (host_id, limit),
        ).fetchall()
    return [item for item in (_snapshot_from_row(row) for row in rows) if item is not None]
