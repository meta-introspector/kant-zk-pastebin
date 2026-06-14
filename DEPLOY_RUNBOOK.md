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
# Full diagnostic report
cd ~/pastebin && bash deploy.sh   # choose 4

# Follow live logs
cd ~/pastebin && bash deploy.sh   # choose 5

# Direct deploy (build + apply + verify)
cd ~/pastebin && bash deploy.sh   # choose 2

# Pipelight deploy
cd ~/pastebin && bash deploy.sh   # choose 1
```

## Deploy (Option 2)

The direct deploy does:

1. `nix build .#systemConfigs.kant-pastebin` — pure build, no network
2. Copies unit file from nix store to `/etc/systemd/system/`
3. `systemctl daemon-reload && systemctl restart kant-pastebin`
4. Runs diagnose automatically for post-deploy verification

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
| Exit code 203/EXEC | Binary garbage collected | Rebuild: `nix build .#systemConfigs.kant-pastebin` then re-apply |
| Service not found | Unit file deleted | Copy from nix store: see deploy option 2 |
| `pastebin-wasm/static` errors | WASM dir missing | Non-fatal, cosmetic only |
| Port 8090 empty, 8081 active | Old beta running, main dead | Deploy main service |

## Recovery from Garbage Collection

If the nix store binary was GC'd:

```bash
cd ~/pastebin
nix build ".#systemConfigs.kant-pastebin" --no-link --print-out-paths
# Get the unit path from services.json
STORE_PATH=$(nix build ".#systemConfigs.kant-pastebin" --no-link --print-out-paths 2>/dev/null)
UNIT_PATH=$(python3 -c "
import json
with open('$STORE_PATH/services/services.json') as f:
    print(json.load(f)['kant-pastebin.service']['storePath'])
")
sudo cp "$UNIT_PATH" /etc/systemd/system/kant-pastebin.service
sudo systemctl daemon-reload
sudo systemctl restart kant-pastebin
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
- **Fix**: Rebuilt `.#systemConfigs.kant-pastebin`, re-applied unit file, restarted service
- **Prevention**: Added `diagnose` command to `deploy.sh` for quick triage
