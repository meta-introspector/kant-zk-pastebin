#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PASTEBIN_DIR="${PASTEBIN_DIR:-$SCRIPT_DIR}"
PASTEBIN_REPO="${PASTEBIN_REPO:-$PASTEBIN_DIR}"
PASTEBIN_BRANCH="${PASTEBIN_BRANCH:-$(git -C "$PASTEBIN_REPO" rev-parse --abbrev-ref HEAD)}"
PASTEBIN_UPSTREAM="$(git -C "$PASTEBIN_REPO" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
if [ -n "$PASTEBIN_UPSTREAM" ]; then
  PASTEBIN_BRANCH="${PASTEBIN_UPSTREAM#*/}"
fi
FLAKE="${PASTEBIN_FLAKE:-git+file://${PASTEBIN_REPO}?ref=${PASTEBIN_BRANCH}#systemConfigs.kant-pastebin-only}"
LOG_DIR="${PASTEBIN_DIR}/logs"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
LOG_FILE="${LOG_DIR}/switch-${TIMESTAMP}.log"

log() {
  local msg="$1"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "[$ts] $msg" | tee -a "$LOG_FILE"
}

mkdir -p "$LOG_DIR"

log "=== Switch started ==="
log "Branch: $PASTEBIN_BRANCH"
log "Flake: $FLAKE"

log "Building system-manager config..."
STORE_PATH="$(nix build "$FLAKE" --no-link --json | jq -r '.[0].outputs.out')"
log "Built: $STORE_PATH"

if [ ! -x "$STORE_PATH/bin/activate" ]; then
  log "ERROR: activation script not found at $STORE_PATH/bin/activate"
  exit 1
fi

log "Activating (requires sudo)..."
sudo "$STORE_PATH/bin/activate" >> "$LOG_FILE" 2>&1
log "Activation OK"

log "Reloading systemd..."
sudo systemctl daemon-reload

log "Restarting kant-pastebin.service..."
sudo systemctl restart kant-pastebin.service >> "$LOG_FILE" 2>&1 || true

log "=== Switch complete ==="
sudo systemctl status kant-pastebin.service --no-pager -l | tee -a "$LOG_FILE"
