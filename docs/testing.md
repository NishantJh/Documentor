# Disposable Test Environment

Documentor can be tested without a Proxmox host or real homelab credentials. The Python `tests` workflow runs automatically on pushes and pull requests using GitHub-hosted Ubuntu runners; it installs the project test dependencies and runs `pytest -q`.

The `container-smoke` workflow is manual-dispatch only and targets the self-hosted Linux x64 runner. It builds the production Dockerfile, starts a container with a throwaway token and synthetic data, and exercises the API. It requires Docker Engine access from that runner. No real homelab endpoint is contacted.

The `windows-recorder-checks` workflow is also manual-dispatch only. It runs the recorder and uploader harnesses in Windows PowerShell 5.1 and PowerShell 7 on the self-hosted Windows x64 runner. Dispatch these two workflows from the GitHub Actions tab only when you intend to use the persistent self-hosted machines.

## What CI verifies

- The Python unit/API tests run automatically for pushes and pull requests on GitHub-hosted Ubuntu runners.
- The Docker image builds and the API starts.
- The health endpoint responds.
- Protected endpoints reject requests without a bearer token.
- A synthetic event can be stored and retrieved.
- Two synthetic snapshots can be stored and compared.
- A Markdown draft report is returned with the expected diff.
- The application runs as a non-root user with a read-only container root filesystem and dropped Linux capabilities.
- On Windows, the recorder and uploader scripts parse, custom and built-in redaction checks work, metadata-only events are queued, expiry cleanup works, and both queue-count and queue-byte limits are enforced.
- The Windows uploader integration test runs against a loopback-only synthetic HTTP server that returns one temporary `503` response followed by success. It verifies the retry preserves `client_event_id`, the queue file is removed only after success, and the uploader reaches its idle state.

The workflow token is test-only. Never copy it into a real deployment.

## Self-hosted runner notes

The Linux runner must have Docker available to the runner account for the manual `container-smoke` workflow. The workflow starts a disposable container named `documentor-ci` and stops it during cleanup. If a previous run is forcibly interrupted, inspect and remove any leftover test container before retrying.

The Windows runner must have Windows PowerShell 5.1 and PowerShell 7 (`pwsh`) installed. The recorder harness uses synthetic data and a temporary directory; it does not start the uploader or call the API.

Self-hosted runners are persistent machines, not disposable hosted VMs. Run only trusted repository workflows on them, avoid exposing production credentials, and review changes before running workflows.

## Run the same test on a Linux workstation

Requirements: Docker Engine with Compose v2, Bash, curl and Python 3. The smoke test creates synthetic data only.

```bash
export HOMELAB_DOCS_API_TOKEN="$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')"
docker compose up --build --detach
```

Wait for the health check to pass, then run:

```bash
bash scripts/smoke-test.sh
```

Expected final output:

```text
PASS: container health, auth, event ingestion/retrieval, snapshots, diff and draft report.
```

Stop the test stack and remove its synthetic database volume when you no longer need it:

```bash
docker compose down --volumes
unset HOMELAB_DOCS_API_TOKEN
```

**Warning:** `docker compose down --volumes` removes the Compose-managed `documentor-test-data` volume. Use this only for this test stack. The Compose file binds the published port to `127.0.0.1`, not to all network interfaces.

## What this does not prove

A successful container smoke test is not a production deployment or a recovery test. It does not validate Caddy/TLS, remote Windows connectivity, host-specific Proxmox/Unraid/OpenWrt collectors, long-running retention, backup restoration, or recovery procedures. Those checks require their respective test environments and evidence.

## Run Windows recorder checks locally

Run the dependency-free recorder checks and uploader retry integration test in separate disposable sessions in both Windows PowerShell 5.1 and PowerShell 7:

```powershell
.\tests\windows\Invoke-RecorderChecks.ps1
.\tests\windows\Test-UploaderRetry.ps1
```

The recorder harness refuses to run if a recorder is already enabled in the session and explicitly disables automatic uploader startup while testing. It does not call the API. The separate uploader test uses a loopback-only synthetic server and temporary DPAPI token; it does not contact the real Documentor API. A workflow definition is not evidence of a passing test; confirm the run result in GitHub Actions.
