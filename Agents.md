# Agent Instructions for Documentor

These instructions apply to AI coding agents and automated contributors working in this repository. Read this file and `plan.md` before making changes.

## Mission and scope

Documentor records evidence about Windows and homelab administration and turns that evidence into accurate, reproducible documentation. Prioritize provenance, security, deterministic behavior and recoverability over speculative automation.

## Required workflow

1. Inspect the existing implementation and relevant tests before editing.
2. Identify the smallest coherent change that advances `plan.md`.
3. State assumptions in code or documentation where they affect behavior.
4. Implement with focused tests; update docs and examples alongside code.
5. Run applicable tests, lint/type checks if configured, and deployment/script validation.
6. Inspect the final diff for regressions, secrets, generated data and unrelated changes.
7. Report what changed, tests actually run, outcomes, known limitations and follow-up tasks. Never claim a test passed unless it was run and passed.

## Evidence and documentation integrity

- Treat raw captured events, logs, screenshots and snapshots as source evidence. Do not silently rewrite or delete them.
- Generate setup/recovery procedures as derived artifacts, not as replacements for raw history.
- Do not infer a command solely from a state diff. Correlate command records, snapshots, timestamps, session/host identity and other evidence.
- Distinguish observed, inferred, candidate and tested statements.
- A failed command is not automatically irrelevant; it may explain a later successful fix.
- A reverted change may be excluded from the main recovery procedure only when evidence supports that classification. Preserve it for troubleshooting.
- Preserve known command order and execution context. If order or prerequisites are uncertain, state that uncertainty.
- Do not claim a recovery procedure is tested unless it was executed successfully in an appropriate environment and the result was recorded.
- Generated docs should be concise, actionable, linked to evidence, and grouped by host, service and procedure.

## Security requirements

- Never commit real inventories, screenshots, terminal transcripts, configuration exports, private addresses when sensitive, credentials, API tokens, private keys, cookies, recovery codes, or database/evidence files.
- Redact secrets before persistence or upload. Avoid collecting secret-bearing command arguments and environment values by default.
- Keep the API private; require authentication for all ingestion and data routes. Fail closed if authentication is not configured.
- Use HTTPS for network transport; do not recommend disabling certificate validation.
- Collectors submit evidence only. The API must not execute commands received from clients.
- Do not implement automatic execution of AI-generated commands. Require explicit human approval for any future action-taking feature.
- Prefer least-privilege and read-only remote credentials. Document required permissions.
- Validate host IDs, path inputs, payload sizes and evidence references. Avoid path traversal and unsafe file writes.
- Treat screenshots, command output and host configuration as sensitive user data.
- Keep secrets outside Git and generated documentation. Use an appropriate secrets store or OS-protected credential storage.

## Engineering quality

- Prefer small modules, typed interfaces, clear names and deterministic functions.
- Use the standard library where practical; justify new dependencies.
- Add tests for new behavior, failure cases, authentication, malformed input, secret redaction and state transitions.
- Keep API schemas backward-compatible where practical; version breaking API changes.
- Use parameterized SQL queries. Never interpolate untrusted values into SQL or shell commands.
- Do not run shell commands from API request payloads or model output.
- Handle partial failures and offline collectors; one unreachable host must not stop collection from others.
- Make retries idempotent where feasible and avoid duplicate evidence on retry.
- Use structured logs without tokens, secrets or full sensitive payloads.
- Ensure database and evidence storage survive application upgrades and service restarts.
- Add migration strategy before making incompatible database schema changes.

## Testing and verification

- Run the focused test suite for each change and the full suite before concluding when feasible.
- Add regression tests for every bug fixed.
- For PowerShell, validate syntax and test on a supported Windows host when possible; do not describe an unexecuted script as runtime-tested.
- For deployment changes, validate shell syntax, service configuration, file permissions, persistent paths and restart behavior.
- For remote collectors, test unavailable hosts, malformed responses, permission failures and secret redaction.
- Report tests that could not be run and why.

## Git and change management

- Keep changes focused and use descriptive commit messages.
- Prefer a feature branch and pull request for substantial changes; do not merge without required checks.
- Never force-push, rewrite shared history, delete user data or change infrastructure without explicit authorization.
- Do not commit runtime state or generated homelab evidence.
- Update `plan.md` when milestone status or priorities materially change.
- Review CI results rather than assuming that a pushed commit passed.

## Definition of done

A change is done when implementation, tests, documentation, security implications and known limitations have been addressed; applicable checks have actually run; and the final report clearly distinguishes verified results from assumptions or work still outstanding.
