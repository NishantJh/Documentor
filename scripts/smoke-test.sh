#!/usr/bin/env bash
set -euo pipefail

base_url="${DOCUMENTOR_URL:-http://127.0.0.1:8765}"
: "${HOMELAB_DOCS_API_TOKEN:?Set HOMELAB_DOCS_API_TOKEN to a throwaway test token}"
auth_header="Authorization: Bearer ${HOMELAB_DOCS_API_TOKEN}"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

echo "Checking health endpoint..."
curl --fail --silent --show-error "$base_url/health" > "$tmpdir/health.json"
python - "$tmpdir/health.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["status"] == "ok", data
assert data["service"] == "documentor", data
PY

echo "Checking authentication..."
status="$(curl --silent --output /dev/null --write-out '%{http_code}' "$base_url/api/v1/events?host_id=synthetic-host")"
test "$status" = "401"

echo "Posting synthetic event..."
curl --fail --silent --show-error -H "$auth_header" -H 'Content-Type: application/json' \
  -d '{"host_id":"synthetic-host","event_type":"configuration_change","summary":"Synthetic DNS change for container smoke test","session_id":"smoke-001","payload":{"test_data":true},"evidence_refs":["synthetic://smoke-test"]}' \
  "$base_url/api/v1/events" > "$tmpdir/event.json"

echo "Posting baseline snapshot..."
curl --fail --silent --show-error -H "$auth_header" -H 'Content-Type: application/json' \
  -d '{"host_id":"synthetic-host","source":"smoke-test","state":{"network":{"dns":"1.1.1.1"}}}' \
  "$base_url/api/v1/snapshots" > "$tmpdir/snapshot1.json"

echo "Posting changed snapshot..."
curl --fail --silent --show-error -H "$auth_header" -H 'Content-Type: application/json' \
  -d '{"host_id":"synthetic-host","source":"smoke-test","state":{"network":{"dns":"9.9.9.9"}}}' \
  "$base_url/api/v1/snapshots" > "$tmpdir/snapshot2.json"
snapshot_id="$(python -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$tmpdir/snapshot2.json")"

echo "Checking snapshot diff..."
curl --fail --silent --show-error -H "$auth_header" \
  "$base_url/api/v1/snapshots/$snapshot_id/diff" > "$tmpdir/diff.json"
python - "$tmpdir/diff.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["baseline"] is not None, data
assert any(item.get("path") == "$.network.dns" and item.get("change") == "changed" for item in data["diff"]), data
PY

echo "Checking event retrieval and report generation..."
curl --fail --silent --show-error -H "$auth_header" \
  "$base_url/api/v1/events?host_id=synthetic-host" > "$tmpdir/events.json"
curl --fail --silent --show-error -H "$auth_header" -X POST \
  "$base_url/api/v1/reports/synthetic-host" > "$tmpdir/report.md"
python - "$tmpdir/events.json" "$tmpdir/report.md" <<'PY'
import json, sys
events = json.load(open(sys.argv[1], encoding="utf-8"))["events"]
report = open(sys.argv[2], encoding="utf-8").read()
assert len(events) == 1, events
assert "Synthetic DNS change for container smoke test" in report
assert "Latest configuration differences" in report
assert "Not yet generated" in report
PY

echo "PASS: container health, auth, event ingestion/retrieval, snapshots, diff and draft report."
