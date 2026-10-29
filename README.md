# Documentor — Homelab Documentation Engine

Documentor is a Windows-first, evidence-backed documentation engine for a multi-machine homelab. It is intended to preserve operational evidence, track configuration snapshots and changes, and produce reviewable Markdown setup and recovery drafts.

Target systems include Windows, Proxmox, Unraid, Incus, OpenWrt and Docker-hosted services.

> **Status: early MVP / development branch.** The API, snapshot diffing, draft reporting, initial Windows inventory collector and opt-in PowerShell command-metadata recorder are implemented. The recorder and latest API hardening have not yet been validated end-to-end on a real Windows workstation. Treat the project as experimental; do not rely on generated reports as tested recovery procedures.

## Features implemented

- **Authenticated FastAPI service:** bearer-token authentication for event and snapshot ingestion, with health endpoint.
- **SQLite persistence:** stores event records and configuration snapshots.
- **Snapshot diffs:** recursively compares JSON snapshots and identifies state changes.
- **Markdown report drafts:** creates draft documentation from recorded data; generated content is not automatically treated as verified.
- **Windows inventory collector:** submits a bounded inventory snapshot covering OS/computer details, BIOS, local disks, network configuration, running services and installed applications.
- **Opt-in PowerShell recorder preview:** records sanitized command metadata for the current PowerShell session, including host/session IDs, timestamp, prior working directory and completion indicators. It does not capture command output, screenshots, browser activity or GUI actions.
- **Local queue and background uploader:** the interactive recorder queues JSON event files locally; a separate PowerShell background job uploads batches, with a per-user mutex, request timeout and retry/defer behaviour.
- **Queue safeguards:** configurable event/byte limits, retention and additive custom redaction patterns. The queue does not evict newer events to make room.
- **API input hardening:** bounded payload sizes/depth, strict schemas, timezone-aware timestamps, idempotent event retries and Markdown output sanitization.
- **Deployment and validation documentation:** includes a Proxmox Debian LXC deployment guide, security notes and Windows recorder/uploader validation harnesses.

## Not implemented or not yet verified

Remote collectors for Proxmox, Unraid, Incus, OpenWrt and Docker; screenshot/output capture; automated classification of reverted or superseded experiments; AI-based event-to-state reconciliation; and verified recovery automation are not implemented. The PowerShell recorder, its background uploader and the latest API changes still require runtime validation. Test scripts in the repository are not evidence that tests have passed.

## Setup

### 1. Deploy the central API

For a persistent homelab installation, deploy the service in a dedicated Debian LXC on Proxmox. The deployment guide covers the service account, Python virtual environment, API token, SQLite persistence, systemd, reverse proxy/TLS and backups:

**[Deployment on Proxmox](docs/deployment-proxmox.md)**

Important security defaults:
- Keep the API on a trusted LAN or behind a private, authenticated HTTPS reverse proxy; do not expose it directly to the internet.
- The service should listen on loopback when deployed behind a reverse proxy.
- Set `HOMELAB_DOCS_API_TOKEN` to a long random secret and `HOMELAB_DOCS_DB` to a persistent database path.
- Do not commit tokens, actual inventories, queue files, configuration exports or other live homelab evidence.

Verify the service health endpoint on the server:

```bash
curl -fsS http://127.0.0.1:8765/health
```

This loopback check verifies the service process; it does not test authenticated client ingestion.

### 2. Configure the Windows client

Use Windows PowerShell 5.1 or PowerShell 7. Clone the repository on the Windows workstation, then run the client setup script from the repository root:

```powershell
.\collector\windows\Set-HomelabDocsClient.ps1
```

Enter the central API URL and bearer token when prompted. Use HTTPS for network connections; plain HTTP is allowed only for loopback development. The script stores configuration under `%LOCALAPPDATA%\HomelabDocs` and protects the token using Windows DPAPI for the current user account.

Do not copy `client.json` or `token.dpapi` into Git or share them. The token is protected for the Windows user who configured it.

### 3. Collect the first Windows inventory snapshot

From the repository root, run:

```powershell
.\collector\windows\collect-inventory.ps1
```

The collector submits an inventory snapshot to the central API. Review the collected fields before using the inventory in documentation; network addresses, installed software and service details can be sensitive.

### 4. Optionally enable PowerShell command metadata recording

The recorder is **opt-in per PowerShell session**. It does not edit your PowerShell profile or start automatically at login. Run it only after configuring the client, and initially use a disposable session with synthetic commands:

```powershell
. .\collector\windows\Enable-HomelabDocsRecorder.ps1
```

The prompt hook records command metadata after commands complete. It does not record command output or screenshots. Events are queued under `%LOCALAPPDATA%\HomelabDocs\queue`; a separate background job uploads them. Heuristic redaction is not a guarantee, so avoid entering credentials while recording and pause recording before sensitive operations.

Available controls:

```powershell
Get-HomelabDocsRecorderStatus
Pause-HomelabDocsRecorder
Resume-HomelabDocsRecorder
Stop-HomelabDocsRecorder
```

- `Pause` stops recording new commands; queued events may still upload.
- `Resume` resumes recording and attempts to drain the queue.
- `Stop` stops recording for the current session and restores the previous prompt where possible. It does not delete queued events or forcibly stop an uploader already draining them.
- Status reports cached queue count/bytes, quota-related event drops and uploader status.

The queue defaults are 5,000 events, 50 MiB and 30 days of retention. These can be adjusted in `%LOCALAPPDATA%\HomelabDocs\client.json`; see [Windows recorder documentation](docs/windows-recorder.md) for supported settings and limitations.

**Do not enable this recorder in your normal admin shell until the Windows validation harness and a live integration test have been run.** The interactive path no longer makes HTTP requests, but the recorder is still experimental and local queue operations can affect prompt latency.

### 5. Validate the recorder

Run both checks from the repository root in separate, disposable sessions, in Windows PowerShell 5.1 and PowerShell 7:

```powershell
.\tests\windows\Invoke-RecorderChecks.ps1
.\tests\windows\Test-UploaderRetry.ps1
```

The recorder harness uses synthetic data and does not start the uploader. The separate uploader test uses a temporary DPAPI token and a loopback-only synthetic server that returns one temporary failure before succeeding; it verifies retry identity and queue cleanup without contacting the real API. These updated checks have not yet been run on the latest commit, so their presence is not evidence of a pass. See [testing documentation](docs/testing.md) for scope and limitations.

## Local development

Python 3.11 or later is recommended. In PowerShell, from the repository root:

```powershell
py -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -e ".[test]"
$env:HOMELAB_DOCS_DB = "$PWD\data\homelab.sqlite3"
$env:HOMELAB_DOCS_API_TOKEN = "replace-with-a-long-random-token"
uvicorn homelab_docs.app:app --app-dir src --host 127.0.0.1 --port 8765
```

This binds the development server to loopback. Use a separate terminal to run client scripts. Do not reuse production credentials for local development.

Run the Python tests with:

```powershell
pytest
```

Do not assume the latest branch passes tests unless you have run them on that revision. GitHub Actions are configured for manual dispatch during development to avoid unnecessary runner usage.

## Documentation

- [Architecture](docs/architecture.md)
- [Proxmox deployment](docs/deployment-proxmox.md)
- [GitHub setup](docs/github-setup.md)
- [Security](docs/security.md)
- [Testing](docs/testing.md)
- [Windows recorder](docs/windows-recorder.md)
- [Roadmap](docs/roadmap.md)
- [Implementation plan](plan.md)

## Security and evidence principles

- Never commit real inventories, screenshots, configuration exports, logs, tokens, local queues or generated evidence.
- Treat command redaction as a heuristic, not a security boundary.
- Keep the API private and use trusted HTTPS for remote connections.
- The API records evidence; it does not execute commands on target hosts.
- Distinguish observed, inferred and tested steps. A snapshot diff shows what changed, not necessarily which command caused it.
- Generated reports are drafts. Do not mark a procedure tested unless it has actually been validated.
