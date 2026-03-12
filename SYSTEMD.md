# Systemd Service Setup

## Installation

```bash
# Copy service file
cp kant-pastebin.service ~/.config/systemd/user/

# Reload systemd
systemctl --user daemon-reload

# Enable and start
systemctl --user enable kant-pastebin.service
systemctl --user start kant-pastebin.service
```

## Configuration

### Environment Variables

- `BIND_ADDR` - Server bind address (default: `127.0.0.1:8090`)
- `UUCP_SPOOL` - Paste storage directory (default: `/mnt/data1/spool/uucp/pastebin`)
- `BASE_PATH` - URL base path for reverse proxy (default: `/pastebin`)
- `RUST_LOG` - Log level (default: `info`)
- `PATH` - Must include IPFS binary location for IPFS integration

### IPFS Integration

The service requires `ipfs` command in PATH for automatic IPFS uploads:

```bash
# Verify IPFS is available
which ipfs

# If using Nix profile
Environment="PATH=/home/USER/.nix-profile/bin:/usr/bin:/bin"

# Or system-wide
Environment="PATH=/usr/local/bin:/usr/bin:/bin"
```

## Management

```bash
# Status
systemctl --user status kant-pastebin.service

# Logs
journalctl --user -u kant-pastebin.service -f

# Restart
systemctl --user restart kant-pastebin.service

# Stop
systemctl --user stop kant-pastebin.service
```

## Nginx Reverse Proxy

Example nginx configuration:

```nginx
location /pastebin/ {
    proxy_pass http://127.0.0.1:8090/;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

## Troubleshooting

### IPFS uploads not working

Check if IPFS is in PATH:
```bash
systemctl --user cat kant-pastebin.service | grep PATH
```

Test IPFS manually:
```bash
echo "test" | ipfs add -Q
```

### Service won't start

Check logs:
```bash
journalctl --user -u kant-pastebin.service -n 50
```

Verify binary exists:
```bash
ls -la /nix/store/*/bin/kant-pastebin
```

### Permission issues

Ensure spool directory exists and is writable:
```bash
mkdir -p /mnt/data1/spool/uucp/pastebin
chmod 755 /mnt/data1/spool/uucp/pastebin
```
