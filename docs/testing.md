# Disposable Test Environment

Documentor can be tested without a Proxmox host or real homelab credentials. The `container-smoke` GitHub Actions workflow builds the production Dockerfile on an ephemeral GitHub-hosted Ubuntu runner, starts a container with a throwaway token and synthetic data, and exercises the API. The runner and container are disposable; no real homelab endpoint is contacted.

## What CI verifies

- The Docker image builds from the repository.
- The API starts and the health endpoint responds.
- Protected endpoints reject requests without a bearer token.
- A synthetic event can be stored and retrieved.
- Two synthetic snapshots can be stored and compared.
- A Markdown draft report is returned with the expected diff.
- The application runs as a non-root user with a read-only container root filesystem and dropped Linux capabilities.

The workflow token is test-only. Never copy it into a real deployment.

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


## Windows recorder checks

Run the dependency-free recorder checks on Windows in both Windows PowerShell 5.1 and PowerShell 7:

```powershell
.\tests\windows\Invoke-RecorderChecks.ps1
```

The harness must run in a separate disposable PowerShell session and refuses to run if a recorder is already enabled. It uses synthetic commands and a temporary directory, does not start the uploader or call the API, and checks both script parsers, prompt/API separation, redaction, metadata-only queueing, expiry cleanup and queue-count enforcement. It has not yet been run in a Windows runtime. Do not treat its presence as evidence of a passing test.
