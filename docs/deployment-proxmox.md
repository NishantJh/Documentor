# Deploy Documentor on Proxmox

This guide deploys the central API in a dedicated Debian 12/13 LXC. Adjust the Debian release to one you already support and test. Do not expose the API directly to the internet.

## 1. Create the LXC

In Proxmox, create a Debian container with:
- An unprivileged container where supported
- A fixed DHCP lease or static LAN address
- A modest initial allocation (for this API, 1 vCPU and 512 MiB–1 GiB RAM is a reasonable starting point)
- A persistent root disk sized for the OS and application only; place growing evidence storage on a separately backed-up mount if needed
- SSH access restricted to your administration LAN

Use a dedicated service account and avoid privileged containers unless a specific verified requirement arises.

## 2. Install the application

Clone the repository and install it into a virtual environment:

```bash
apt update
apt install -y python3 python3-venv python3-pip git
adduser --system --group --home /opt/documentor documentor
install -d -o documentor -g documentor /opt/documentor/app /var/lib/documentor
git clone https://github.com/NishantJh/Documentor.git /opt/documentor/app
chown -R documentor:documentor /opt/documentor/app
sudo -u documentor python3 -m venv /opt/documentor/venv
sudo -u documentor /opt/documentor/venv/bin/pip install /opt/documentor/app
```

## 3. Configure secrets and persistence

Create an environment file readable only by root:

```bash
install -m 600 /dev/null /etc/documentor.env
openssl rand -hex 32
nano /etc/documentor.env
```

Put the generated value in this file as HOMELAB_DOCS_API_TOKEN. Also set HOMELAB_DOCS_DB=/var/lib/documentor/homelab.sqlite3. Never put the token in Git.

## 4. systemd service

Create /etc/systemd/system/documentor.service:

```ini
[Unit]
Description=Documentor Homelab Documentation API
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=documentor
Group=documentor
WorkingDirectory=/opt/documentor/app
EnvironmentFile=/etc/documentor.env
ExecStart=/opt/documentor/venv/bin/uvicorn homelab_docs.app:app --app-dir /opt/documentor/app/src --host 127.0.0.1 --port 8765
Restart=on-failure
RestartSec=5
UMask=0077
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/documentor

[Install]
WantedBy=multi-user.target
```

Enable the service:

```bash
systemctl daemon-reload
systemctl enable --now documentor
systemctl status documentor
curl -fsS http://127.0.0.1:8765/health
```

The API binds to loopback, so remote access must go through a reverse proxy or a deliberate private-network binding. If using Caddy, proxy to 127.0.0.1:8765 and use a trusted TLS certificate. Restrict access at the router/firewall to your LAN or VPN. Do not disable certificate validation on Windows.

## 5. Persistence and backup

The database lives at /var/lib/documentor/homelab.sqlite3. Back up the database consistently (SQLite online backup or stop the service before copying), plus any evidence directory you configure later. Store a copy outside this LXC and verify restoration periodically. Git contains application source, not actual homelab data.

## 6. First Windows client

From the repository checkout on Windows, run collector/windows/Set-HomelabDocsClient.ps1 and enter the HTTPS URL and bearer token. Then run collector/windows/collect-inventory.ps1. The inventory collector submits a bounded Windows inventory snapshot. An opt-in PowerShell command-metadata recorder preview is documented in `docs/windows-recorder.md`; it is not yet validated on your workstation and does not capture command output or screenshots.

## 7. Operational checks

- Check logs with journalctl -u documentor -e.
- Confirm /health locally and from the approved client path.
- Confirm unauthenticated calls to protected endpoints fail.
- Confirm the database remains after service restart.
- Restore a backup to a test location before relying on it.
