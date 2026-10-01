---
name: nginx-management
description: >-
  Nginx management for solana.solfunmeme.com — SSL, upload limits, research-grade
  error logging, and error documents as research artifacts. Private server with
  unlimited uploads, LE SSL certs, structured logs, and an error document archive.
  Use when fixing nginx config, debugging SSL, enabling large uploads, or
  analyzing nginx error patterns.
---

# Nginx Management — solana.solfunmeme.com

## Architecture

```
                      ┌──────────────────────────┐
                      │   system-manager flake    │
                      │  pastebin-system-manager  │
                      └──────────┬───────────────┘
                                 │
          ┌──────────────────────┼──────────────────────┐
          │                      │                      │
          ▼                      ▼                      ▼
   ┌──────────────┐    ┌──────────────┐    ┌──────────────────┐
   │  nginx.conf   │    │  SSL certs   │    │  Research logs   │
   │  (nix store)  │    │  (LE + self) │    │  + error docs    │
   └──────────────┘    └──────────────┘    └──────────────────┘
```

## Key Configuration

| Setting | Value | Why |
|---------|-------|-----|
| `client_max_body_size` | `0` (unlimited) | Private server, single user |
| `ssl_certificate` | `/etc/letsencrypt/live/solana.solfunmeme.com/fullchain.pem` | Let's Encrypt via Namecheap DNS-01 |
| `access_log` | `/var/log/nginx/research.access.log` research | Structured research-grade logging |
| `error_log` | `/var/log/nginx/research.error.log` warn | All warnings+errors captured |
| `error-docs` | `/var/log/nginx/error-docs/error.log` | All non-2xx responses as documents |
| HTTP→HTTPS | Auto-redirect (301) | forceSSL = true |

## SSL Certificate Management

Two services manage SSL:

1. **`ssl-selfsigned.service`** — runs before nginx, ensures `/etc/letsencrypt/live/` has symlinks (either to LE archive or self-signed fallback)
2. **`certbot-renew.service`** + timer — daily check, renews LE certs via Namecheap DNS-01, re-symlinks latest

The system-manager nix config uses **runtime** path resolution (not build-time `builtins.pathExists`) to avoid baking stale cert paths into the immutable nix store.

### SSL Troubleshooting

```bash
# Check which cert nginx is serving
echo | openssl s_client -connect 127.0.0.1:443 -servername solana.solfunmeme.com 2>&1 | grep -E "subject=|issuer="

# Should show issuer=C=US, O=Let's Encrypt, CN=YR1 for LE cert
# If issuer=CN=solana.solfunmeme.com, self-signed fallback is active

# Fix symlinks manually
sudo systemctl start ssl-selfsigned.service
sudo systemctl reload nginx
```

## Upload Limits

Since this is a private server with a single user, all upload size limits are disabled:

- **Global nginx**: `client_max_body_size 0` (unlimited)
- **Per-location** `/pastebin/`: `client_max_body_size 0`
- **Proxy timeouts**: 3600s for read/send/connect
- **Buffering**: `proxy_buffering off; proxy_request_buffering off;`

## Research Error Logging

### Access Log Format (research)

```
"$time_iso8601" client=$remote_addr method=$request_method uri=$request_uri status=$status body_bytes=$body_bytes_sent referer=$http_referer user_agent=$http_user_agent request_time=$request_time upstream_addr=$upstream_addr upstream_status=$upstream_status scheme=$scheme host=$host
```

Logged to: `/var/log/nginx/research.access.log`

### Error Log

All warnings and errors: `/var/log/nginx/research.error.log`

### Error Documents (all non-2xx responses)

Structured entries go to `/var/log/nginx/error-docs/error.log`:

```
=== Error Document ===
Date: $time_iso8601
Client: $remote_addr
Method: $request_method
URI: $request_uri
Status: $status
Bytes: $body_bytes_sent
Referer: $http_referer
User-Agent: $http_user_agent
Request-Time: $request_time
Upstream-Addr: $upstream_addr
Upstream-Status: $upstream_status
Host: $host
X-Forwarded-For: $http_x_forwarded_for
Server-Name: $server_name
-------------------
```

Browse live at: `https://solana.solfunmeme.com/nginx-docs/errors/`

## Deploy Commands

```bash
cd /mnt/data1/kant/pastebin

# Commit changes
git add -A && git commit -m "description of changes"

# Build + activate
bash deploy.sh switch

# Restart nginx if config changed (nix store paths are immutable)
sudo systemctl restart nginx.service

# Test config
sudo nginx -t -c /nix/store/*-nginx.conf

# Check status
systemctl status nginx.service --no-pager -l
```

## Log Analysis Workflow

```bash
# Recent errors
sudo tail -50 /var/log/nginx/research.error.log

# Error documents
sudo tail -50 /var/log/nginx/error-docs/error.log

# Research access log — find slow requests
sudo awk -F' ' '$8 > 5 {print}' /var/log/nginx/research.access.log | sort -k8 -rn | head -10

# Count errors by status code
sudo grep "^=== Error Document ===" /var/log/nginx/error-docs/error.log | wc -l

# Extract unique error URIs
sudo grep "^URI:" /var/log/nginx/error-docs/error.log | sort | uniq -c | sort -rn

# Watch errors in real time
sudo tail -f /var/log/nginx/error-docs/error.log
```

## Related Skills

- [[skills/nginx-control-tiles]] — Nginx topology → DASL control tiles
- [[skills/nginx-tile-route]] — Add/list/reload nginx tile routes
- [[skills/unified-nginx-deploy]] — Pattern for a single flake owning all nginx routes
- [[skills/port-registry]] — Live port scan dashboard
- [[skills/pastebin-large-post-workflow]] — Pastebin large post split/share behavior

## Shmem Cross-References

| Keyword | Description |
|---------|-------------|
| ssl_certificate | Path to LE cert (runtime, not build-time) |
| client_max_body_size | Set to 0 for unlimited uploads |
| log_format research | Structured access log for research |
| error_doc | Structured error document format |
| /nginx-docs/errors/ | Live error document browser |
