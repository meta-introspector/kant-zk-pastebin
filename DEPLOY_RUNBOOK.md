# Kant Pastebin — Deploy Runbook

> Operational guide for deploying, diagnosing, and recovering the Kant Pastebin service.

## Architecture

```
Internet → nginx (443) → /pastebin/ → kant-pastebin (:8090)
                                       /pastebin/beta/ → kant-pastebin-beta (:8150)
```

| Component | Port | Service | Binary |
|-----------|------|---------|--------|
| Main pastebin | 8090 | `kant-pastebin.service` | `nix store .../kant-pastebin-0.1.0/bin/kant-pastebin` |
| Beta pastebin | 8150 | `kant-pastebin-beta.service` | (separate instance) |
| Legacy beta | 8081 | `kant-pastebin-beta` (PID 1250) | Old process, no unit file |

## Quick Commands

```bash
# Build the application binary from the flake
nix build .#kant-pastebin --print-out-paths

# Build system-manager config, activate it, restart the service, and diagnose
./deploy.sh

# Restart only the installed service, then diagnose
./deploy.sh restart

# Full diagnostic report without rebuilding
./diagnose.sh
```

## Deploy

`deploy.sh` resolves the physical repository directory with `pwd -P` and defaults to that path. Do not deploy from the old home symlink path or from `/home/mdupont/pastebin/target/release`.

The deploy flow does:

1. `nix build "$PASTEBIN_FLAKE" --no-link --json`
   - default `PASTEBIN_FLAKE` is `$PASTEBIN_DIR#systemConfigs.kant-pastebin-only`
2. Runs the generated `activate` script from the nix store
3. `sudo systemctl daemon-reload`
4. `sudo systemctl restart kant-pastebin.service`
5. Runs `./diagnose.sh` for post-deploy verification

If nix-daemon was killed by OOM during a build, restart it before retrying:

```bash
sudo -n systemctl start nix-daemon.service
```

## Diagnose (Option 4)

The diagnose command checks 8 areas:

1. **Service status** — active/inactive, PID, uptime for both main and beta
2. **Port bindings** — 8090, 8081, 8150 (is anything listening?)
3. **Nginx proxy mapping** — which URL path maps to which backend
4. **HTTP health checks** — curl on all ports + public endpoint
5. **Last deploy info** — unit file, binary path, timestamps
6. **Recent journal logs** — last 30 lines from journald
7. **System-manager activation** — result symlink, build time
8. **Data paths** — existence and size of working dirs

### Common Failure Patterns

| Symptom | Cause | Fix |
|---------|-------|-----|
| HTTP 502 from public | Nothing on :8090 | `sudo systemctl restart kant-pastebin` |
| Exit code 203/EXEC | Binary garbage collected | Rebuild with `./deploy.sh` |
| Service not found | Unit file deleted | Rebuild and apply with `./deploy.sh` |
| `pastebin-wasm/static` errors | WASM dir missing | Non-fatal, cosmetic only |
| Port 8090 empty, 8081 active | Old beta running, main dead | Deploy main service |

## Recovery from Garbage Collection

If the nix store binary was GC'd, rebuild and re-apply through the repo deploy script:

```bash
./deploy.sh
```

For a manual binary check:

```bash
nix build .#kant-pastebin --no-link --print-out-paths
```

## Environment Variables

| Variable | Value | Purpose |
|----------|-------|---------|
| `BIND_ADDR` | `127.0.0.1:8090` | Listen address |
| `BASE_PATH` | `/pastebin` | URL prefix |
| `BASE_URL` | `https://solana.solfunmeme.com` | Public origin |
| `UUCP_SPOOL` | `/mnt/data1/spool/uucp/pastebin` | UUCP store |
| `PIPELIGHT_CMD` | nix store path | Pipelight binary for tile rendering |
| `TILES_DIR` | colon-separated nix paths | Tile plugin libraries |
| `RUST_LOG` | `info` | Log level |

## Incident History

### 2026-06-01: Bad Gateway (502)

- **Cause**: Unit file deleted from `/etc/systemd/system/` on May 30 during system-manager activation. Old binary was garbage collected.
- **Symptoms**: HTTP 502 on `/pastebin/`, nothing listening on :8090
- **Fix**: Rebuilt the system-manager config, re-applied the unit file, restarted service
- **Prevention**: Added `diagnose.sh` to `deploy.sh` for quick triage

### 2026-06-20: Large Post Split/Share Hardening

- **Cause**: Post split loaded the full raw paste into the browser, returned every chunk body as JSON, and rendered chunk previews in the DOM. This could hang the server/browser for ~10MB posts.
- **Symptoms**: Split page stalled or returned oversized responses; Share failed in browsers without `navigator.share`.
- **Fix**: Added server-side `POST /api/split-paste`, made `split-download` and `split-upload` accept `paste_id`, limited split previews to metadata plus a small excerpt, and added `sharePost()` fallback URL copying.
- **Prevention**: Post split page now keeps raw content server-side, exposes chunk-size and boundary dropdowns, and downloads a ZIP containing only `part_*.txt` files.
