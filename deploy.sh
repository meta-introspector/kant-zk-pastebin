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

  NORA_DEV_FLAKE="${PASTEBIN_DEV_FLAKE:-git+file://${PASTEBIN_REPO}?ref=${PASTEBIN_BRANCH}#devShells.default}"

  log "Step 1b: Optional nora registry check (for local cargo build)"
  NORA_URL="$(grep -A1 '\[registries.nora\]' .cargo/config.toml 2>/dev/null | grep 'index' | cut -d'=' -f2 | tr -d ' \"' || true)"
  if [ -n "$NORA_URL" ] && curl -sf --max-time 5 "$NORA_URL" > /dev/null 2>&1; then
    log "Nora registry reachable. Running cargo build check via git+file devShell."
    nix develop "$NORA_DEV_FLAKE" -c cargo build --release >> "$LOG_FILE" 2>&1 || log "WARNING: cargo build failed, but nix build succeeded — proceeding."
  else
    log "Nora registry not reachable. Skipping cargo build check (nix build already verified compilation)."
  fi

  log "Step 2: Git commit and push"
  git add -A
  git commit -m "deploy: auto-commit before nix build $(date -u +%Y-%m-%dT%H:%M:%SZ)" || true
  git push origin "$PASTEBIN_BRANCH" || true

  log "Step 3b: Verify git push succeeded"
  LOCAL_HEAD="$(git rev-parse HEAD)"
  REMOTE_HEAD="$(git ls-remote origin "$PASTEBIN_BRANCH" | cut -f1)"
  if [ "$LOCAL_HEAD" != "$REMOTE_HEAD" ]; then
    log "ERROR: Local HEAD ($LOCAL_HEAD) does not match remote ($REMOTE_HEAD). Push may have failed."
    exit 1
  fi
  log "Git push verified: $LOCAL_HEAD"

  log "Step 4: Nix build system-manager config from git source: $FLAKE"
  SM_STORE_PATH="$(nix build "$FLAKE" --no-link --json | jq -r '.[0].outputs.out')"
  log "Built: $SM_STORE_PATH"

  if [ ! -x "$SM_STORE_PATH/bin/activate" ]; then
    log "ERROR: activation script not found at $SM_STORE_PATH/bin/activate"
    exit 1
  fi

  log "Activating system-manager configuration"
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

  log "=== Deploy complete ==="
  "$PASTEBIN_DIR/diagnose.sh" | tee -a "$LOG_FILE"
}

restart_pastebin() {
  run_sudo systemctl restart kant-pastebin.service
  "$PASTEBIN_DIR/diagnose.sh"
}

switch_system_manager() {
  cd "$PASTEBIN_DIR"

  echo "=== Switch: build + activate system-manager config ==="
  echo "Flake: $FLAKE"

  echo "Building system-manager config..."
  STORE_PATH="$(nix build "$FLAKE" --no-link --json | jq -r '.[0].outputs.out')"
  echo "Built: $STORE_PATH"

  if [ ! -x "$STORE_PATH/bin/activate" ]; then
    echo "ERROR: activation script not found at $STORE_PATH/bin/activate" >&2
    exit 1
  fi

  echo "Activating (requires sudo)..."
  run_sudo "$STORE_PATH/bin/activate"

  echo "Reloading systemd..."
  run_sudo systemctl daemon-reload

  echo "Restarting kant-pastebin.service..."
  run_sudo systemctl restart kant-pastebin.service || true

  echo ""
  echo "Switch complete."
  run_sudo systemctl status kant-pastebin.service --no-pager -l
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
