# Documentor — Homelab Documentation Engine

Documentor is a self-hosted, evidence-backed documentation service for recording and understanding changes across a homelab. The central service stores ordered events and timestamped configuration snapshots, compares successive snapshots, and generates reviewable Markdown report drafts.

The initial client targets Windows. The wider design is intended to support Proxmox, Unraid, Incus, OpenWrt and Docker hosts as additional collectors are developed.

> **Current scope:** This is an early MVP. The working Windows collector uploads a bounded system inventory snapshot. It does not yet record arbitrary desktop activity, terminal history, screenshots or every configuration change automatically. Generated reports are drafts, not validated recovery instructions.

## What it does

- Collects selected Windows computer, OS, BIOS, disk, network, running-service and installed-application details.
- Stores submitted events and snapshots in a central SQLite database.
- Calculates recursive JSON differences between successive snapshots for a host.
- Generates Markdown report drafts using available events and recent snapshot differences.
- Keeps collection separate from execution: the API does not execute commands submitted by clients.

## Architecture

A typical deployment contains:

1. **Central service:** FastAPI application running on a private Debian LXC or another trusted host.
2. **Persistent store:** SQLite database containing events and snapshots.
3. **Collectors:** scripts running on target machines. The initial Windows collector uses PowerShell and Windows management interfaces.
4. **Documentation output:** API-generated Markdown drafts and snapshot diffs, which can be reviewed and maintained alongside operational documentation.

There is no web-based administration dashboard at this stage. Interact with the service through its HTTP API and supplied scripts.

## Quick start: deploy the central service

For a persistent homelab deployment, follow the [Proxmox deployment guide](docs/deployment-proxmox.md). It covers a dedicated Debian LXC, service account, Python virtual environment, systemd, token configuration, reverse proxy considerations and backups.

The essential server settings are:

- **HOMELAB_DOCS_API_TOKEN:** a long random bearer token shared with authorised collectors.
- **HOMELAB_DOCS_DB:** SQLite database path. For a server deployment, use a persistent location such as /var/lib/documentor/homelab.sqlite3.

Keep the API on a trusted network. For remote clients, use HTTPS with a certificate trusted by the client machine. Do not expose the service directly to the public internet.

Verify the service after startup:

~~~bash
curl -fsS https://YOUR-DOCUMENTOR-HOST/health
~~~

A healthy service returns JSON similar to:

~~~json
{"status":"ok","service":"documentor","version":"0.1.0"}
~~~

The health endpoint is unauthenticated. Data endpoints require the bearer token.

## Windows client: first-time setup

The initial Windows collector is in the collector/windows directory and is designed to work with Windows PowerShell 5.1 and PowerShell 7.

### 1. Get the client scripts

Clone the repository on the Windows machine:

~~~powershell
git clone https://github.com/NishantJh/Documentor.git
Set-Location .\Documentor
~~~

### 2. Register the client

Run:

~~~powershell
.\collector\windows\Set-HomelabDocsClient.ps1
~~~

When prompted:

- Enter the base URL of the Documentor service, for example https://docs.homelab.example. Include the scheme and hostname; do not append an API path.
- Enter the bearer token configured on the server.

The script creates %LOCALAPPDATA%\HomelabDocs\client.json and token.dpapi. The token is stored as a Windows DPAPI-protected secure string for the current Windows user account. Run setup under the same Windows account that will run the collector.

Use HTTPS for network connections. The setup script permits HTTP only for localhost development. Do not bypass certificate validation; install or trust the appropriate certificate on the Windows client if validation fails.

### 3. Collect and upload the initial inventory

Run:

~~~powershell
.\collector\windows\collect-inventory.ps1
~~~

The script submits a snapshot to POST /api/v1/snapshots. A successful response includes a snapshot ID and stored=true. The host ID is the lower-case Windows computer name. Keep the returned snapshot ID if you want to inspect its diff.

The current inventory includes:
- Computer manufacturer, model, hostname, domain and physical memory
- Windows edition, version, build, architecture and last boot time
- BIOS manufacturer and version
- Fixed local disks, filesystem, capacity, free space and volume name
- Network interface descriptions, IPv4 addresses, gateways and DNS servers
- Running Windows services
- Installed applications and available version, publisher and installation-location metadata

It does not collect command history, screenshots, file contents or passwords by design. Inventory still contains operationally sensitive information, including host, network and software details. Protect the server, database and backups accordingly.

### 4. Collect subsequent snapshots

Run the same collector after a meaningful system or configuration change, or at a cadence you choose:

~~~powershell
.\collector\windows\collect-inventory.ps1
~~~

Each successful run submits another snapshot for the same host. Documentor compares a snapshot with the preceding snapshot for that host. The first snapshot is the baseline and has no earlier snapshot to compare against.

The MVP does not install a scheduled task automatically. If recurring collection is required, create and manage a Windows Task Scheduler task yourself, using the same Windows account that ran client setup. Verify manual uploads before scheduling it.

## Using the API

All endpoints are relative to the base URL of your Documentor service. Protected endpoints require this header:

~~~http
Authorization: Bearer YOUR_API_TOKEN
~~~

Do not paste real tokens into shared terminals, screenshots, tickets or source control.

| Method | Endpoint | Purpose |
| --- | --- | --- |
| GET | /health | Service health; no token required |
| POST | /api/v1/snapshots | Submit a host snapshot |
| GET | /api/v1/snapshots/{snapshot_id}/diff | Compare a snapshot with the preceding snapshot for that host |
| POST | /api/v1/events | Submit an operational event |
| GET | /api/v1/events?host_id={host_id}&limit=100 | Retrieve events for a host |
| POST | /api/v1/reports/{host_id} | Generate a Markdown report draft for a host |

### Generate a report

In PowerShell, replace the URL, token and host ID:

~~~powershell
$baseUrl = "https://YOUR-DOCUMENTOR-HOST"
$token = "YOUR_API_TOKEN"
$hostId = "your-windows-hostname".ToLowerInvariant()
$headers = @{ Authorization = "Bearer $token" }

Invoke-RestMethod -Method Post `
  -Uri "$baseUrl/api/v1/reports/$hostId" `
  -Headers $headers |
  Set-Content -Encoding UTF8 ".\$hostId-report.md"
~~~

The endpoint returns Markdown text. Review the generated file and corroborate important steps against the underlying evidence before relying on it. The report uses the events and recent snapshot difference currently available to the service; it is not an automatically verified recovery procedure.

### Inspect a snapshot difference

Use the numeric snapshot ID returned by the collector:

~~~powershell
$snapshotId = 2
Invoke-RestMethod -Method Get `
  -Uri "$baseUrl/api/v1/snapshots/$snapshotId/diff" `
  -Headers $headers
~~~

The response identifies the host, snapshot, baseline snapshot (if one exists) and differing paths. A difference establishes that two observed states differ; it does not establish which command or action caused the change.

### Submit an event

The event endpoint accepts structured event data defined by the API schema. It is available for integrations and future collectors, but the current Windows inventory script does not automatically capture terminal commands or GUI actions. Consult src/homelab_docs/schemas.py before building an event producer.

## Development and tests

Requirements: Python 3.11 or later.

On Windows PowerShell:

~~~powershell
py -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -e ".[test]"
$env:HOMELAB_DOCS_DB = "$PWD\data\homelab.sqlite3"
$env:HOMELAB_DOCS_API_TOKEN = "replace-with-a-long-random-token"
uvicorn homelab_docs.app:app --app-dir src --host 127.0.0.1 --port 8765
~~~

In a second terminal:

~~~powershell
.\.venv\Scripts\Activate.ps1
pytest
~~~

The local API is available at http://127.0.0.1:8765. The interactive FastAPI schema is at /docs during development. Do not bind a development instance to all network interfaces without applying the deployment security controls.

## Troubleshooting

- **Client is not configured:** run Set-HomelabDocsClient.ps1 under the same Windows user account that runs the inventory collector.
- **401 Invalid bearer token:** confirm that the client token matches HOMELAB_DOCS_API_TOKEN on the server. Re-run client setup if the token changed.
- **503 API token is not configured:** the server process does not have HOMELAB_DOCS_API_TOKEN set. Check the systemd environment file and restart the service.
- **HTTPS or certificate error:** verify the URL, reverse-proxy route and certificate trust chain. Do not disable TLS validation.
- **Connection refused or timeout:** check service status, reverse-proxy routing, firewall rules and DNS resolution.
- **Snapshot upload fails:** check the API URL, token, TLS trust and network path. Confirm service health, then inspect server logs with journalctl -u documentor -e.
- **No changes appear in a diff:** confirm that a later snapshot was uploaded for the same host ID and that the changed property is included in the current inventory. A first snapshot is only a baseline.

## Security, privacy and backups

- Keep the API private; do not expose it directly to the internet.
- Use HTTPS for all non-localhost client connections.
- Use a long, random API token and restrict access to it. Rotate it if exposed and update client configuration.
- Protect the SQLite database and backups. They contain infrastructure inventory and may reveal sensitive network and software details.
- Do not commit live inventories, screenshots, configuration exports, logs, database files, tokens or private keys.
- Redact secrets before submitting any event or snapshot from a custom integration.
- Back up the database outside the Documentor LXC and periodically test restoration.
- Treat generated reports as drafts. Distinguish observed, inferred and tested steps; validate recovery instructions before execution.

## Project documentation

- [Architecture](docs/architecture.md)
- [Proxmox deployment](docs/deployment-proxmox.md)
- [GitHub development workflow](docs/github-setup.md)
- [Security](docs/security.md)
- [Roadmap](docs/roadmap.md)

## Current limitations and roadmap

The MVP provides authenticated event and snapshot ingestion, SQLite persistence, recursive JSON diffs, Markdown report drafts and an initial Windows inventory collector.

The following capabilities are **not yet implemented**: general desktop recording, complete terminal interception, remote host collectors, automatic classification of reverted experiments, AI-assisted reconciliation and verified recovery automation. The Windows collector is inventory-only and does not automatically record arbitrary changes. Do not interpret a generated report as a validated recovery runbook.

Contributions should preserve evidence provenance, avoid collecting secrets by default and keep observed facts distinct from inferred explanations.
