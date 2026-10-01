# Deployment Configuration

## Upload Limits

The pastebin service has **unlimited upload sizes** configured:

- Nginx: `client_max_body_size 0` (no limit)
- Nginx proxy timeouts: 3600s read/send/connect
- Systemd service: `TimeoutStartSec=0`, `TimeoutStopSec=0`, `TimeoutAbortSec=0` (no timeout)

## Deployment Methods

```bash
# Build the application binary from the flake
nix build .#kant-pastebin --print-out-paths

# Build system-manager config, activate it, restart the service, and diagnose
./deploy.sh

# Restart only the installed service, then diagnose
./deploy.sh restart

# Diagnose without rebuilding
./diagnose.sh
```

`deploy.sh` resolves the repository path from the script location, so run it from the repo checkout. Do not deploy from the old `/home/mdupont/pastebin/target/release` path.

## System-Manager Configuration

Located in `system-manager-config.nix`:

- Service timeouts set to 0 (unlimited)
- Nginx proxy timeouts: 3600s
- WebSocket support enabled for `/pastebin/` location

## Troubleshooting

### 504 Gateway Timeout

If uploads return 504, check:

1. Nginx timeouts: `proxy_read_timeout`, `proxy_send_timeout`, `proxy_connect_timeout` must be set
2. Systemd timeouts: `TimeoutStartSec`, `TimeoutStopSec`, `TimeoutAbortSec` must be 0
3. Service running: `sudo systemctl status kant-pastebin`
4. Health endpoint: `curl http://127.0.0.1:8090/health`