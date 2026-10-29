# Architecture

## Design principle

The primary output is a reproducible recovery procedure. The primary inputs are an ordered event ledger, machine configuration snapshots, diffs, screenshots, deployment files and verification results. Diffs alone cannot reconstruct command order or establish why a setting changed.

## Data layers

1. Raw evidence: append-only events, terminal records, screenshots, source configuration snapshots and logs. Preserve provenance and timestamps.
2. Reconciled state: latest known state per host/service, state transitions, dependencies, and classifications such as retained, reverted, superseded, failed or uncertain.
3. Published documentation: editable Markdown derived from evidence, containing only relevant steps while linking back to evidence.

Never discard raw evidence when removing an experiment from the recovery guide.

## Event envelope

Each event should carry a stable host ID, source machine, timestamp, session ID, event type, action or command, exit status, bounded output, evidence references and redaction status. Preserve execution context such as working directory and target host when available. Do not collect secrets by default.

## Snapshot model

Snapshots are timestamped and source-labelled JSON objects. Collectors should normalize volatile fields and redact credentials before upload. The diff engine compares successive snapshots and identifies added, removed and modified paths. Keep the exact source snapshot alongside the diff.

## Reconciliation

Correlate command events and GUI evidence with before/after snapshots using host identity, timestamps and session context. Classification must be conservative:
- retained: supported as part of final intended state
- reverted: state returned to earlier value
- superseded: replaced by a later approach
- failed: command/action did not succeed
- uncertain: evidence is insufficient

A failed action can still be a prerequisite to a later successful correction; a reverted experiment can still be valuable troubleshooting evidence. Keep uncertainty visible and require review when impact is high.

## Security boundaries

Collectors submit evidence; the API does not execute uploaded commands. Keep the service private, authenticate ingestion, use HTTPS for remote traffic, redact secrets and back up state off-host. GitHub stores source and sanitized examples, not real homelab evidence.
