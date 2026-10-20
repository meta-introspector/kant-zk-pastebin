# Deploy Beta Site Documentation

## Overview

This directory contains the beta deployment setup for Kant Pastebin. The beta site runs on port 8081 and is accessible at `/pastebin/beta/` in the main nginx configuration.

## What's Generated

### deploy-beta.sh

The `deploy-beta.sh` script automates the beta deployment process:

1. **Version Info**: Extracts git commit, build time, and displays the version
2. **Build**: Runs `make dev` to build the release binary (via nix develop)
3. **Nginx Config**: Generates `/pastebin/beta/` nginx configuration for beta access
4. **Systemd Service**: Creates `kant-pastebin-beta.service` for the beta version
5. **Summary**: Shows deployment details and next steps

### Key Features

- **Separate Port**: Beta runs on port 8081 (main pastebin uses 8090)
- **Version Visibility**: Shows git commit hash and build time
- **Safe Deployment**: Can run alongside the production site
- **Config Files**: Self-documenting with clear paths and next steps

## Deployment Steps

### Quick Setup

```bash
# Build and deploy beta version
./deploy-beta.sh

# Copy nginx config (do this once)
cp nginx-beta/pastebin-beta.conf /etc/nginx/conf.d/

# Install systemd service
cp kant-pastebin-beta.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable kant-pastebin-beta
systemctl start kant-pastebin-beta

# Test beta site
curl http://127.0.0.1:8081/api/version
```

### After Running deploy-beta.sh

The following files are generated:

1. `target/release/kant-pastebin` - Built binary
2. `nginx-beta/pastebin-beta.conf` - Nginx configuration for beta
3. `kant-pastebin-beta.service` - Systemd service file

### Testing

Check that the beta version is working:

```bash
# Get version info from beta
curl http://127.0.0.1:8081/api/version

# Check if beta site is accessible
# Should return beta version with git commit info
```

### Configuration

#### Nginx Config

The generated `nginx-beta/pastebin-beta.conf` contains:

```nginx
location /pastebin/beta/ {
    proxy_pass http://127.0.0.1:8081/;
    # ... other proxy settings ...
    add_header X-Pastebin-Beta-Version "v0.2.0";
    add_header X-Pastebin-Beta-Commit "<git-commit>";
}
```

#### Systemd Service

The `kant-pastebin-beta.service` file:

- Runs on port 8081
- Uses the same binary as production
- Shows beta version in systemd service description
- Includes all necessary environment variables

## Version Info

The beta version includes:

- Git commit hash (from git rev-parse HEAD)
- Build timestamp (ISO 8601 format)
- Binary path
- Rust version

Example output from `curl http://127.0.0.1:8081/api/version`:

```json
{
  "name": "kant-pastebin",
  "version": "0.2.0",
  "git_commit": "c28a1336fe0f7d3b2b5c3e0b7d9a2e4f6c5b8d9",
  "build_time": "2026-10-17T14:32:18Z",
  "binary": "/mnt/data1/kant/pastebin/target/release/kant-pastebin",
  "rustc": "1.80.0",
  "nix_build": true
}
```

## Running the Beta

### Development vs Production

| Feature | Production | Beta |
|---------|------------|------|
| Port | 8090 | 8081 |
| Nginx Path | `/pastebin/` | `/pastebin/beta/` |
| Version | v0.2.0 | v0.2.0 |
| Access | Public | Public |

### Testing Beta Features

You can test beta features by accessing `/pastebin/beta/`:

```bash
# Test basic functionality
curl -I http://127.0.0.1:8081/api/version

# Test search
curl "http://127.0.0.1:8081/api/search?q=test&page=1&per_page=20"

# Test upload endpoint (returns 403 for curl)
curl -X POST http://127.0.0.1:8081/paste -d "test content" -H "Content-Type: text/plain"
```

## Managing the Beta

### Update Beta Version

```bash
# Update git version info
cd /mnt/data1/kant/pastebin
./deploy-beta.sh

# Reload systemd
cp target/release/kant-pastebin /mnt/data1/kant/pastebin/target/release/kant-pastebin-beta 2>/dev/null || true
systemctl restart kant-pastebin-beta
```

### Monitor Beta Logs

```bash
# Check beta logs
systemctl status kant-pastebin-beta
systemctl journalctl -u kant-pastebin-beta --follow
```

### Stop Beta

```bash
systemctl stop kant-pastebin-beta
systemctl disable kant-pastebin-beta
```

## Integration with Main System

### Full Deployment Script

The beta can be fully deployed by:

1. Running `./deploy-beta.sh` to generate config files
2. Adding the nginx config to the main nginx configuration
3. Installing and starting the systemd service
4. Testing the beta at `https://domain.com/pastebin/beta/`

### Environment Variables

The beta uses the same environment variables as production:

```bash
export BIND_ADDR=127.0.0.1:8081
export UUCP_SPOOL=/mnt/data1/spool/uucp/pastebin
export BASE_PATH=/pastebin
export BASE_URL=https://solana.solfunmeme.com
export NFT_DIR=/mnt/data1/time-2026/03-march/13/nft_enriched
export ENRICH_PIPELINE=/mnt/data1/time-2026/03-march/09/mmgroup-rust/enrich-qid.sh
export RUST_LOG=info
```

## Troubleshooting

### Service Won't Start

```bash
# Check logs
systemctl status kant-pastebin-beta
systemctl journalctl -u kant-pastebin-beta

# Check if port is in use
netstat -tlnp | grep :8081
```

### Nginx Configuration Errors

```bash
# Test nginx config syntax
nginx -t

# Check nginx error log
tail -f /var/log/nginx/error.log
```

### Beta Version Mismatch

If the beta version doesn't match the expected format:

```bash
# Check git commit
cd /mnt/data1/kant/pastebin
./deploy-beta.sh  # This will regenerate config with current git commit
```

## Git Commit Tracking

The beta deployment tracks the exact git commit that was built:

- Git commit: Stored in systemd service environment
- Build time: ISO 8601 timestamp when deployed
- Version tracking: Each beta deployment is version-specific

### Version History

Each time `deploy-beta.sh` runs, it captures the current git state, allowing you to track:

- When beta features were deployed
- What git commit each beta version corresponds to
- Build timestamps for rollback scenarios

## Production Considerations

### Canary Testing

The beta can be used for canary testing:

1. Deploy beta with new features
2. Test in production environment
3. Monitor performance and user feedback
4. Gradually roll out if successful

### Rollback Plan

If issues are discovered:

```bash
# Rollback to previous version (if systemd keeps history)
systemctl restart kant-pastebin-beta
# Or copy the previous binary:
cp /previous/path/to/kant-pastebin /target/release/kant-pastebin
systemctl restart kant-pastebin-beta
```

## Beta Release Workflow

1. **Development**: Code changes made
2. **Build**: `./deploy-beta.sh` captures git state and builds
3. **Test**: Access `https://domain.com/pastebin/beta/` for testing
4. **Deploy**: Add nginx config, start service
5. **Monitor**: Check logs and health

## Maintenance

### Regular Updates

```bash
# Weekly version check
cd /mnt/data1/kant/pastebin
./deploy-beta.sh

# Monthly cleanup (remove old log files)
find /var/log/kant-pastebin -name "*.log.*" -mtime +30 -delete
```

### Security

The beta deployment uses the same security settings as production:

- No new privileges (`NoNewPrivileges=true`)
- Private temporary files (`PrivateTmp=true`)
- Protected kernel tunables and modules
- Read-only root filesystem

## Summary

The `deploy-beta.sh` script provides a complete, documented deployment system for the Kant Pastebin beta site. It handles:

- Version tracking with git commit hashes
- Separate nginx configuration for beta access
- Systemd service management
- Clear documentation and next steps
- Safe parallel deployment with production

This enables rapid testing and deployment of beta features while maintaining version control and operational safety.