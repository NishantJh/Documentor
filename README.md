# Documentor — Homelab Documentation Engine

Windows-first, evidence-backed documentation for a multi-machine homelab. The central service stores ordered events and configuration snapshots, calculates diffs, and generates Markdown drafts with evidence links.

Targets include Windows, Proxmox, Unraid, Incus, OpenWrt and Docker-hosted services.

## Status

Early MVP: authenticated FastAPI event/snapshot ingestion, SQLite persistence, recursive JSON diffs, draft report generation, and an initial Windows inventory collector. An opt-in PowerShell command-metadata recorder preview and disposable Docker smoke tests are also present on this development branch. The recorder has not been validated on a real Windows workstation.

Not yet implemented: output or screenshot capture, remote host collectors, automatic classification of reverted experiments, AI reconciliation, or verified recovery automation. Generated reports are drafts, not validated recovery instructions.

## Development

Python 3.11+ recommended.

```powershell
py -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -e "[test]"
$env:HOMELAB_DOCS_DB = "$PWD\data\homelab.sqlite3"
$env:HOMELAB_DOCS_API_TOKEN = "replace-with-a-long-random-token"
uvicorn homelab_docs.app:app --host 127.0.0.1 --port 8765
```

Run tests with `pytest`.

## Docs

- docs/architecture.md
- docs/deployment-proxmox.md
- docs/github-setup.md
- docs/security.md
- docs/testing.md
- docs/windows-recorder.md
- docs/roadmap.md

## Security

Never commit real inventories, screenshots, configuration exports, logs, tokens or generated evidence. Redact secrets before ingestion. Keep the API on a trusted network or behind authenticated HTTPS. The API records evidence and does not execute commands on target hosts. Label observed, inferred and tested steps distinctly; a diff shows what changed, not necessarily which command caused it.
