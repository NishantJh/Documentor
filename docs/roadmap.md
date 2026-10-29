# Implementation roadmap

## Stage 0 — Foundation
- [x] Repository and source layout
- [x] Authenticated event/snapshot API
- [x] SQLite persistence and JSON diffs
- [x] Draft Markdown report
- [ ] Confirm deployment on Proxmox

## Stage 1 — Reliable Windows capture
- PowerShell command/session capture with explicit opt-in and redaction
- Inventory snapshots and event timestamps
- Screenshots at session checkpoints
- Target host/session association for SSH and browser activity
- Windows service/startup integration

## Stage 2 — Remote state collectors
- Proxmox API and configuration snapshots
- Unraid and Docker state
- Incus instances/profiles/networks
- OpenWrt UCI exports
- Snapshot scheduling, retention and secret redaction

## Stage 3 — Reconciliation
- Ordered event ledger with source provenance
- Reverted/superseded/failed/retained classifications
- Correlate actions to before/after diffs
- Keep raw evidence immutable; generated docs are derived artifacts
- Confidence and manual correction mechanisms

## Stage 4 — Recovery documentation
- Dependency graph and recovery ordering
- Procedure generation from event history plus state
- Verification commands and expected outputs
- Safe test environment checks
- Mark procedures tested only after successful validation

## Stage 5 — Interface and operations
- Searchable local web UI
- Backup/restore and retention controls
- Drift and stale-documentation reports
- CI security and quality checks
