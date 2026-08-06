# Deploy Script Tasks

## Completed

### 1. Remove `--max-time 5` from Nora health check curl
- **Status**: Done
- **Change**: Removed `--max-time 5` from `curl -sf http://127.0.0.1:4000/health` in `deploy.sh`
- **Reason**: The 5-second timeout caused the health check to fail silently when the Nora registry was slow to respond

### 2. Add enhanced logging to deploy.sh
- **Status**: Done
- **Changes**:
  - Added `log_err()` function for error-level messages
  - Added `log_cmd()` function for running commands with full output logging
  - Added binary path verification before service restart
  - Added systemd unit file contents logging after activation
  - Added service status checks after each restart
  - Added build output logging to the log file

## Open Tasks

### 3. Fix system-manager activation timeout
- **Status**: Open
- **Problem**: `system-manager activate` times out waiting for systemd jobs during deploy
- **Symptoms**: "Timeout waiting for systemd jobs" error in deploy log
- **Investigation needed**: Check if `systemctl daemon-reload` or `systemctl restart` is hanging
- **Possible fix**: Add timeout to system-manager activation or run activation in background

### 4. Fix kant-pastebin.service "command vanished" after deploy
- **Status**: Open
- **Problem**: After deploy, `kant-pastebin.service` reports "Current command vanished from the unit file"
- **Symptoms**: Service fails to start because the Nix store binary path no longer exists
- **Root cause**: The system-manager activation creates a unit file pointing to a Nix store path, but the path changes after each build. The old path gets garbage collected.
- **Possible fix**: Ensure the deploy script verifies the binary exists at the unit file's ExecStart path before restarting, or add a post-activation verification step

### 5. Add deploy.sh self-test mode
- **Status**: Open
- **Problem**: No way to verify deploy.sh works without running a full deploy
- **Possible fix**: Add a `--dry-run` or `--test` mode that validates the environment without making changes