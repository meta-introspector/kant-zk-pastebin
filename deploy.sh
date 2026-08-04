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
LOG_FILE="${LOG_DIR}/deploy-${TIMESTAMP}.log"

log() {
  local msg="$1"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "[$ts] $msg" | tee -a "$LOG_FILE"
}

run_sudo() {
  if [ "${EUID}" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

usage() {
  cat <<USAGE
Usage: $0 [deploy|restart|switch] [--sudo]

Commands:
  deploy    Nix build check, optional cargo build (if nora reachable), git commit+push, nix build, activate, restart, diagnose
  restart   Restart the installed pastebin service, then diagnose
  switch    Build + activate system-manager config with sudo (alias for switch.sh)
  --sudo    Run deploy steps that need root via sudo (auto-detected if not root)

Options:
  --sudo    Force sudo even if already root
USAGE
}

deploy() {
  cd "$PASTEBIN_DIR"
  mkdir -p "$LOG_DIR"

  log "=== Deploy started ==="
  log "Branch: $PASTEBIN_BRANCH"
  log "Flake: $FLAKE"

  log "Step 1: Nix build check (verifies Rust compilation with vendored deps)"
  if ! nix build .#kant-pastebin --no-link >> "$LOG_FILE" 2>&1; then
    log "ERROR: Nix build failed. Cannot proceed without compileable codebase."
    exit 1
  fi
  log "Step 1: Nix build OK"

  log "Step 1b: Cargo build check via nix develop"
  if curl -sf --max-time 5 http://127.0.0.1:4000/health > /dev/null 2>&1; then
    log "Nora registry reachable at localhost:4000. Running cargo build via nix develop."
    nix develop . -c cargo build --release >> "$LOG_FILE" 2>&1 || log "WARNING: cargo build failed, but nix build succeeded — proceeding."
  else
    log "Nora registry not reachable at localhost:4000. Skipping cargo build check (nix build already verified compilation)."
  fi

  log "Step 2: Git commit (local only, no remote push)"
  git add -A
  git commit -m "deploy: auto-commit before nix build $(date -u +%Y-%m-%dT%H:%M:%SZ)" || true
  log "Local commit verified: $(git rev-parse HEAD)"

  log "Step 4: Nix build system-manager config from git source: $FLAKE"
  SM_STORE_PATH="$(nix build --impure "$FLAKE" --no-link --json | jq -r '.[0].outputs.out')"
  log "Built: $SM_STORE_PATH"

  if [ ! -x "$SM_STORE_PATH/bin/activate" ]; then
    log "ERROR: activation script not found at $SM_STORE_PATH/bin/activate"
    exit 1
  fi

  log "Activating system-manager configuration"
  run_sudo rm -f /etc/systemd/system/kant-pastebin.service \
                    /etc/systemd/system/nginx.service \
                    /etc/systemd/system/nginx-log-setup.service \
                    /etc/systemd/system/ssl-selfsigned.service \
                    /etc/systemd/system/certbot-renew.service \
                    /etc/systemd/system/certbot-renew.timer
  if ! run_sudo "$SM_STORE_PATH/bin/activate" >> "$LOG_FILE" 2>&1; then
    log "ERROR: system-manager activation failed — service restart skipped"
    exit 1
  fi
  log "Activation OK"
  run_sudo systemctl daemon-reload

  log "Restarting pastebin application service"
  if ! run_sudo systemctl restart kant-pastebin.service >> "$LOG_FILE" 2>&1; then
    log "WARNING: kant-pastebin.service restart failed — unit may not be loaded yet. Check: systemctl status kant-pastebin.service"
  fi

  log "Restarting svg2anim-worker service"
  if ! run_sudo systemctl restart svg2anim-worker.service >> "$LOG_FILE" 2>&1; then
    log "WARNING: svg2anim-worker.service restart failed — unit may not be loaded yet. Check: systemctl status svg2anim-worker.service"
  fi

  log "=== Deploy complete ==="
  "$PASTEBIN_DIR/diagnose.sh" | tee -a "$LOG_FILE"
}

restart_pastebin() {
  run_sudo systemctl restart kant-pastebin.service
  "$PASTEBIN_DIR/diagnose.sh"
}

switch_system_manager() {
  cd "$PASTEBIN_DIR"

  echo "=== Switch: build + activate pastebin system-manager config ==="
  echo "Flake: $FLAKE"

  echo "Building pastebin package..."
  nix build .#kant-pastebin --no-link >> "$LOG_FILE" 2>&1 || true
  echo "Building system-manager config..."
  STORE_PATH="$(nix build --impure "$FLAKE" --no-link --json | jq -r '.[0].outputs.out')"
  echo "Built: $STORE_PATH"

  if [ ! -x "$STORE_PATH/bin/activate" ]; then
    echo "ERROR: activation script not found at $STORE_PATH/bin/activate" >&2
    exit 1
  fi

  echo "Activating (requires sudo)..."
  run_sudo "$STORE_PATH/bin/activate"

  echo "Reloading systemd..."
  run_sudo systemctl daemon-reload

  echo "Restarting pastebin..."
  run_sudo systemctl restart kant-pastebin.service 2>/dev/null || true

  echo ""
  echo "=== Verifying ==="
  if systemctl is-active --quiet kant-pastebin.service 2>/dev/null; then
    echo "  ✅ kant-pastebin.service"
  else
    echo "  ⚠️  kant-pastebin.service not active"
  fi
}

case "${1:-deploy}" in
  deploy)
    deploy
    ;;
  restart)
    restart_pastebin
    ;;
  switch)
    switch_system_manager
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
