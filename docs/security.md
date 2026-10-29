# Security and evidence handling

## Trust boundaries

The Windows and remote collectors are clients. The API stores evidence and must never execute commands from request bodies. Keep the API on the homelab LAN, behind HTTPS and authentication, or bound to loopback for local development.

## Secrets

Do not store passwords, bearer tokens, private keys, cookies, recovery codes or unredacted environment files in Git, screenshots, event payloads or generated Markdown. Redact before upload. Treat configuration exports as sensitive even when obvious secrets are removed.

## Persistence and backups

Keep the SQLite database, raw evidence and generated documentation on persistent storage outside the source checkout. Back up the database and evidence off-host; test restoration. GitHub should contain application source and sanitized examples only.

## Documentation integrity

Preserve raw evidence separately from generated procedures. Label observed, inferred and tested steps distinctly. Never classify a failed command as unnecessary solely because it failed once. A reverted change may be diagnostically important. Require review or safe validation before marking recovery instructions as tested.
