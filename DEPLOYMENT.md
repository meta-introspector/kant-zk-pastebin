# Deployment Configuration

## Upload Limits

The pastebin service has **unlimited upload sizes** configured:

- Nginx: `client_max_body_size 0` (no limit)
- Nginx proxy timeouts: 3600s read/send/connect
- Systemd service: `TimeoutStartSec=0`, `TimeoutStopSec=0`, `TimeoutAbortSec=0` (no timeout)

## Deployment Methods

```
bash deploy.sh           # Interactive menu (options 1-5)
bash deploy.sh           # Option 4: Diagnose
bash deploy.sh           # Option 5: Live logs
nix run .#pipelight -- run deploy      # Background orchestration
nix run .#pipelight -- run full-deploy # Build + deploy via pipelight
```

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