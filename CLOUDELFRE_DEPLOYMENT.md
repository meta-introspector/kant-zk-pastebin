# Cloudflare Deployment for Kant Pastebin

## Overview
This document describes the Cloudflare deployment setup for the Kant Pastebin service,
including systemd services, nginx proxy, and Cloudflare Workers managed via SOPS.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Cloudflare Workers                        │
│  ┌──────────────────┐  ┌─────────────────────────────────┐  │
│  │ kant-zk-relay-   │  │ kant-zk-pastebin-wasm           │  │
│  │ wasm             │  │ (Rust WASM)                     │  │
│  │ (Durable Objects)│  │                                 │  │
│  └──────────────────┘  └─────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                      Kant Account                            │
│  Account ID: 2c5da35f915a13c131bead97f3f7bc75                │
│  API Token:  (managed via SOPS)                              │
└─────────────────────────────────────────────────────────────┘
```

## Components

### 1. Systemd Services
Two systemd services manage the local services:

**kant-pastebin.service** - Rust actix-web server
- Port: 127.0.0.1:8090
- Spool: /mnt/data1/spool/uucp/pastebin
- Base path: /pastebin

**kant-relay.service** - Node.js rendezvous relay
- Port: 127.0.0.1:8787
- Uses Durable Object protocol compatible with Cloudflare twin

### 2. Nginx Proxy
- Proxies `/pastebin/` to the Rust server on port 8090
- Handles reverse proxy headers (X-Real-IP, X-Forwarded-For)

### 3. Cloudflare Workers
- `kant-zk-relay-wasm` - Lean WASM relay with Durable Objects (ROOMS)
- `kant-zk-pastebin-wasm` - Rust WASM pastebin tool
- KV namespace: WASM_KV for WASM caching
- Assets: Web UI served from same origin (no CORS needed)

## Setup Steps

### Step 1: Encrypt Cloudflare Credentials with SOPS
```bash
./scripts/setup-cloudflare-credentials.sh
```
This will:
- Prompt for Cloudflare API Token (no special characters shown)
- Prompt for Cloudflare Account ID
- Encrypt credentials using SOPS with PGP keys:
  - A76A0CF9079EC60D
  - 445EB57704130B8D
- Save to `.sops/credentials.sops.yaml`

### Step 2: Deploy Systemd Services
```bash
sudo ./scripts/deploy-all.sh systemd
```
This installs, enables, and starts:
- kant-pastebin.service
- kant-relay.service

### Step 3: Configure Nginx
```bash
sudo ./scripts/deploy-all.sh nginx
```
This:
- Copies the nginx config to /etc/nginx/sites-available/
- Creates the symlink in sites-enabled
- Tests the nginx configuration
- Reloads nginx

### Step 4: Deploy Cloudflare Workers
```bash
./scripts/deploy-all.sh cloudflare
```
This:
- Verifies SOPS credentials are present
- Runs deploy-cloudflare-worker.sh
- Deploys both workers

### Step 5: Verify Everything
```bash
./scripts/deploy-all.sh verify
```

## Full Deployment
```bash
sudo ./scripts/deploy-all.sh all
```

## SOPS Configuration

The SOPS configuration is defined in `.sops.yaml`:
- Cloudflare credentials: `.sops/cloudflare-*.yaml`
- Worker secrets: `.sops/worker-*.yaml`
- Database credentials: `.sops/database-*.yaml`
- TLS/SSL: `.sops/tls-*.yaml`
- IPFS/storage: `.sops/storage-*.yaml`

All encrypted with PGP keys A76A0CF9079EC60D and 445EB57704130B8D.

## Troubleshooting

### Cloudflare Account Over Quota
If you see an error about the account being over quota:
1. Check your Cloudflare dashboard for quota status
2. Delete unused Workers or KV namespaces
3. Upgrade your Cloudflare plan if needed

### SOPS Decryption Errors
If SOPS fails to decrypt:
```bash
sops --decrypt .sops/credentials.sops.yaml
```
Make sure your GPG keyring has the required keys.

### Service Not Starting
Check the systemd logs:
```bash
sudo journalctl -u kant-pastebin.service -f
sudo journalctl -u kant-relay.service -f
```

### Nginx Configuration Error
Test the nginx configuration:
```bash
sudo nginx -t
```
Check the error messages and fix the config file.

## Monitoring

Check worker status in Cloudflare Dashboard:
- Workers & Pages: https://dash.cloudflare.com/?to=/:account/workers-and-pages
- KV Namespaces: https://dash.cloudflare.com/?to=/:account/storage/kv/namespaces

## Security Considerations

1. The SOPS credentials file is encrypted and should not be committed
2. GPG keys should be stored securely (not in the repo)
3. The systemd services run with restricted permissions
4. Nginx proxies only to localhost, not exposed directly

