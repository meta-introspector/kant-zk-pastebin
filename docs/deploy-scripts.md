# Deployment Scripts

This document explains the deployment scripts in the kant-pastebin repository: `deploy.sh` and `deploy-beta.sh`.

---

## Table of Contents

- [deploy.sh](#deploysh)
- [deploy-beta.sh](#deploy-betahs)
- [Quick Reference](#quick-reference)
- [Environment Variables](#environment-variables)
- [Systemd Service Files](#systemd-service-files)
- [Nginx Configuration](#nginx-configuration)
- [Troubleshooting](#troubleshooting)

---

## deploy.sh

`deploy.sh` is the main deployment script for routine builds and pushes. It handles both production-style branch pushes and beta service restarts.

### Usage

```bash
# Default: build, commit, push to current branch
./deploy.sh

# Deploy to beta service (systemd)
./deploy.sh --target deploy-beta

# Alias for deploy-beta
./deploy.sh --target beta

# Push to a specific branch
./deploy.sh --target main

# Show help
./deploy.sh --help
```

### What It Does

1. **Builds the project** — runs `make build` (which calls `nix build .#kant-pastebin`).
2. **Commits changes** — stages all working-tree changes (`git add -A`), then commits if `git diff --cached --quiet` reports staged changes. Uses a timestamped commit message.
3. **Deploys** based on the `--target`:
   - `deploy-beta` or `beta` → restarts the `kant-pastebin-beta` systemd service.
   - Empty target → pushes the current branch to `origin`.
   - `<branch-name>` → pushes to `origin/<branch-name>`.

### Arguments

| Argument | Description | Default |
|---|---|---|
| `--target` | Deployment target: `deploy-beta`, `beta`, `<branch>`, or empty | *(empty → push current branch)* |
| `--target=VALUE` | Same form with `=` | *(as above)* |
| `--help`, `-h` | Show usage | — |

### Logging

All log lines are timestamped in ISO 8601 UTC:

```
[2026-10-20T15:29:23Z] Building kant-pastebin...
[2026-10-20T15:29:35Z] Committing changes...
[2026-10-20T15:29:35Z] Changes committed
[2026-10-20T15:29:40Z] Deployment complete!
```

### Makefile Integration

The Makefile ties several deploy workflows together:

```makefile
deploy:
	bash deploy.sh deploy              # calls with target "deploy"

restart:
	systemctl restart kant-pastebin.service
	systemctl restart svg2anim-worker.service
	systemctl status kant-pastebin.service --no-pager
```

> **Note**: `make deploy` uses target name `deploy`, which now falls into the `*` case in the script and pushes to `origin/deploy`. To push to your current branch instead, use `./deploy.sh` with no `--target`.

### Prerequisites

- `nix` with the flake inputs available (for `make build`)
- `git` push access to the remote
- For beta deployments: the `kant-pastebin-beta.service` systemd unit must be installed (see [deploy-beta.sh](#deploy-betahs))

---

## deploy-beta.sh

`deploy-beta.sh` is a self-contained, full-featured beta deployment script. It is **the recommended way** to deploy the beta site.

### Usage

```bash
# Full deployment (build + nginx + systemd + verify)
./deploy-beta.sh

# Skip the build step (binary already present from a prior run)
./deploy-beta.sh --no-build

# Use a custom backend port
./deploy-beta.sh --port 8095

# Show help
./deploy-beta.sh --help
```

### What It Does

| Step | Description |
|---|---|
| 1. Build | Runs `nix develop -c cargo build --release` (falls back to `cargo build --release` without nix). Captures `GIT_COMMIT` and `BUILD_TIME`. |
| 2. Nginx snippet | Writes `nginx-beta/pastebin-beta.conf` with the `/pastebin/beta/` location block, proxy headers, timeouts, and version headers. |
| 3. Install nginx | Copies the snippet into `/etc/nginx/services.d/` (or the merged dir), with deduplication via backup. |
| 4. Systemd unit | Generates `kant-pastebin-beta.service` with all env vars (`UUCP_SPOOL`, `BIND_ADDR`, `PORT`, `BASE_PATH`, `BASE_URL`, `GIT_COMMIT`, `BUILD_TIME`, etc.) and installs it. |
| 5. Start service | Restarts via `systemctl`, with a `nohup` fallback if systemd fails. |
| 6. Verify | Checks the backend API (`/api/version`) and the public URL (`/pastebin/beta/api/version`). Reloads nginx. |

### Arguments

| Argument | Description |
|---|---|
| `--no-build` | Skip cargo build |
| `--port 8095` | Override `BETA_PORT` |
| `--port=8095` | Same form with `=` |
| `-h`, `--help` | Show help |

### Environment Overrides

| Variable | Default | Description |
|---|---|---|
| `BETA_PORT` | `8085` | Backend port for the beta service |
| `PASTEBIN_DOMAIN` | `solana.solfunmeme.com` | Public domain |
| `NGINX_SERVICES_DIR` | `/etc/nginx/services.d` | Nginx snippet install directory |
| `NGINX_MERGED_DIR` | `/etc/nginx-sm-merged/services.d` | Alternate nginx dir |
| `PASTEBIN_DIR` | script directory | Project root |
| `UUCP_SPOOL` | `/mnt/data1/spool/uucp/pastebin` | Shared spool directory |

### Two Fixes Made on 2026-10-28

Both were found while deploying the archive-pattern build; each made a redeploy look successful when it was not.

- **Stop with sudo.** `systemctl stop` needs root on this host. The script only tried `sudo` for `start`, so `stop` silently failed, the old process kept the port, and `start` was a no-op — a redeploy appeared to succeed while the old binary kept serving. It now falls back to `sudo systemctl stop`.
- **Bind to loopback.** The unit used `BIND_ADDR=0.0.0.0:${BETA_PORT}`. Nginx proxies `/pastebin/beta/` locally, so the backend has no reason to listen on a public interface; it now binds `127.0.0.1`.

Both matter for verification: `curl …/pastebin/beta/api/version` reports the `build_time` baked in at compile time, so a stale `build_time` is the tell that the restart did not take.

### Logging Functions

`deploy-beta.sh` defines its own helper functions:

- `log()` — `[$TIMESTAMP] message`
- `section()` — prints a `=== heading ===` divider
- `die()` — logs an error and exits 1
- `as_root()` — runs a command with `sudo` if the target isn't writable

---

## Quick Reference

| Task | Command |
|---|---|
| Push current branch | `./deploy.sh` |
| Deploy & restart beta | `./deploy-beta.sh` |
| Deploy beta (skip build) | `./deploy-beta.sh --no-build` |
| Deploy beta (custom port) | `./deploy-beta.sh --port 8095` |
| Restart service only | `systemctl restart kant-pastebin.service` |
| Restart beta service | `systemctl restart kant-pastebin-beta.service` |
| View beta service logs | `journalctl -u kant-pastebin-beta -f` |
| Check beta API version | `curl http://127.0.0.1:8085/api/version` |
| Check public beta | `curl https://solana.solfunmeme.com/pastebin/beta/api/version` |

---

## Environment Variables

These variables are consumed by the application at runtime via `env::var()` and are also injected by the systemd unit files:

| Variable | Default | Used in | Description |
|---|---|---|---|
| `UUCP_SPOOL` | `/var/spool/uucp` | both | Spool directory for pastes, archive sessions, search index |
| `BASE_PATH` | `""` | both | URL prefix for routing (e.g. `/pastebin/beta`) |
| `BASE_URL` | `http://localhost:8090` | both | External URL for links |
| `BIND_ADDR` | `0.0.0.0:8090` | both | Address to bind |
| `PORT` | `8090` | both | Port to listen on |
| `GIT_COMMIT` | `"unknown"` | both | Embed in HTML footer for version display |
| `BUILD_TIME` | `"unknown"` | both | Build timestamp for version footer |
| `RUST_LOG` | `info` | both | Log level |

### Shared Spool Path

Both prod and beta services share `/mnt/data1/spool/uucp/pastebin` as `UUCP_SPOOL`:

```
/mnt/data1/spool/uucp/pastebin/
├── index.jsonl              # paste index
├── archive_sessions/        # persistent archive sessions (JSON)
├── tantivy/                 # search index
└── ...
```

This means archive sessions and search state are shared between prod and beta.

---

## Systemd Service Files

### kant-pastebin.service (production)

```ini
[Unit]
Description=Kant Pastebin

[Service]
Type=simple
WorkingDirectory=<PASTEBIN_DIR>
ExecStart=<binary> --bind 0.0.0.0 --port 8090
Restart=always
RestartSec=10
Environment="UUCP_SPOOL=..."
Environment="BASE_PATH=..."
...
```

Key settings:
- `TimeoutStartSec=0` / `TimeoutStopSec=0` — unlimited (supports large uploads)
- Restart-always policy for uptime

### kant-pastebin-beta.service (beta, on port 8085)

```ini
[Unit]
Description=Kant Pastebin Beta
After=network.target

[Service]
Type=simple
WorkingDirectory=<PASTEBIN_DIR>
ExecStart=<binary>
Restart=always
RestartSec=10
Environment="UUCP_SPOOL=..."
Environment="BIND_ADDR=0.0.0.0:8085"
Environment="PORT=8085"
Environment="BASE_PATH=/pastebin/beta"
Environment="BASE_URL=..."
Environment="RUST_LOG=info"
Environment="GIT_COMMIT=..."
Environment="BUILD_TIME=..."
TimeoutStartSec=0
TimeoutStopSec=0
NoNewPrivileges=true
PrivateTmp=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true

[Install]
WantedBy=default.target
```

---

## Nginx Configuration

### Production

Defined in `kant-pastebin.nginx`, proxies `/pastebin/` to the backend.

### Beta

Generated by `deploy-beta.sh` into `nginx-beta/pastebin-beta.conf`:

```nginx
location /pastebin/beta/ {
    proxy_pass http://127.0.0.1:8085/;
    proxy_http_version 1.1;
    ...
    client_max_body_size 0;
    proxy_read_timeout 3600s;
    ...
    add_header X-Pastebin-Beta-Version "v0.2.0";
    add_header X-Pastebin-Beta-Commit "<git-commit>";
}
```

The snippet supports both the merged-nginx layout (`/etc/nginx-sm-merged/services.d/`) and the standard layout (`/etc/nginx/services.d/`), trying the merged dir first.

---

## Troubleshooting

### `log: command not found`

You are running an older version of `deploy.sh` that is missing the `log()` function definition. Upgrade to the current version.

### `git push origin deploy` fails

The `--target deploy` form pushes to a branch named `deploy` which may not exist. Use `./deploy.sh` with no `--target` to push to the current branch.

### Commit not created after build

`deploy.sh` compares `git diff --cached --quiet` after `git add -A`. If there are no staged changes (everything was already committed), the commit step is skipped. Check with `git diff --cached --stat`.

### Beta service won't start

```bash
sudo systemctl status kant-pastebin-beta --no-pager
sudo journalctl -u kant-pastebin-beta -n 50
```

### Backend not answering after deploy

```bash
# Check if the binary is running
ps aux | grep kant-pastebin
# Check the port
ss -tlnp | grep 8085
# Test directly
curl http://127.0.0.1:8085/api/version
```

### Nginx not reloading

```bash
# Check nginx config syntax
nginx -t
# Reload manually
sudo systemctl reload nginx
# Or try the signal form
sudo nginx -s reload
```
