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

# Use the pastebin-only config which now includes nora services too.
# This prevents activating pastebin from removing nora's systemd units.
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

log_err() {
  local msg="$1"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "[$ts] ERROR: $msg" | tee -a "$LOG_FILE" >&2
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
  deploy    Nix build pastebin, cargo build check, git commit, build + activate
            all-services system-manager config (pastebin + nora + tiles + svg + nginx),
            restart services, diagnose
  restart   Restart pastebin + svg2anim-worker services, then diagnose
  switch    Build + activate all-services system-manager config with sudo

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
  log "Pastebin dir: $PASTEBIN_DIR"
  log "Log file: $LOG_FILE"

  log "Step 1: Nix build check (verifies Rust compilation with vendored deps)"
  local build_output
  build_output="$(nix build .#kant-pastebin --no-link 2>&1)" || {
    log_err "Nix build failed. Cannot proceed without compileable codebase."
    log "BUILD OUTPUT: $build_output"
    exit 1
  }
  log "Step 1: Nix build OK"

  log "Step 1b: Cargo build check via nix develop"
  if curl -sf http://127.0.0.1:4000/health > /dev/null 2>&1; then
    log "Nora registry reachable at localhost:4000. Running cargo build via nix develop."
    nix develop . -c cargo build --release >> "$LOG_FILE" 2>&1 || log "WARNING: cargo build failed, but nix build succeeded — proceeding."
  else
    log "Nora registry not reachable at localhost:4000. Skipping cargo build check (nix build already verified compilation)."
  fi

  log "Step 2: Git commit (local only, no remote push)"
  git add -A
  git commit -m "deploy: auto-commit before nix build $(date -u +%Y-%m-%dT%H:%M:%SZ)" || true
  log "Local commit verified: $(git rev-parse HEAD)"

  log "Step 3: Nix build system-manager config: $FLAKE"
  SM_STORE_PATH="$(nix build --impure "$FLAKE" --no-link --json 2>>"$LOG_FILE" | jq -r '.[0].outputs.out')" || {
    log_err "system-manager config build failed"
    exit 1
  }
  log "Built: $SM_STORE_PATH"

  if [ ! -x "$SM_STORE_PATH/bin/activate" ]; then
    log_err "activation script not found at $SM_STORE_PATH/bin/activate"
    exit 1
  fi

  log "Step 4: Activating system-manager configuration (pastebin + nora + svg2anim)"
  if ! run_sudo "$SM_STORE_PATH/bin/activate" >> "$LOG_FILE" 2>&1; then
    log_err "system-manager activation failed — service restart skipped"
    exit 1
  fi
  log "Activation OK"
  run_sudo systemctl daemon-reload

  log "Step 5: Restarting services"
  run_sudo systemctl restart kant-pastebin.service >> "$LOG_FILE" 2>&1 || log "WARNING: kant-pastebin.service restart failed"
  run_sudo systemctl restart svg2anim-worker.service >> "$LOG_FILE" 2>&1 || log "WARNING: svg2anim-worker.service restart failed"
  run_sudo systemctl restart nora-dir.service >> "$LOG_FILE" 2>&1 || log "WARNING: nora-dir.service restart failed"
  run_sudo systemctl restart nora.service >> "$LOG_FILE" 2>&1 || log "WARNING: nora.service restart failed"

  log "=== Deploy complete ==="
  "$PASTEBIN_DIR/diagnose.sh" | tee -a "$LOG_FILE"
}

restart_pastebin() {
  run_sudo systemctl restart kant-pastebin.service
  run_sudo systemctl restart svg2anim-worker.service
  "$PASTEBIN_DIR/diagnose.sh"
}

switch_system_manager() {
  cd "$PASTEBIN_DIR"

  echo "=== Switch: build + activate all-services system-manager config ==="
  echo "Flake: $FLAKE"

  echo "Building pastebin package..."
  nix build .#kant-pastebin --no-link >> "$LOG_FILE" 2>&1 || true

  echo "Updating pastebin-src in system-manager flake.lock..."
  cd "$SYSTEM_MANAGER_DIR"
  nix flake update pastebin-src >> "$LOG_FILE" 2>&1 || true

  echo "Building system-manager config..."
  STORE_PATH="$(nix build --impure "$FLAKE" --no-link --json 2>>"$LOG_FILE" | jq -r '.[0].outputs.out')"
  echo "Built: $STORE_PATH"

  if [ ! -x "$STORE_PATH/bin/activate" ]; then
    echo "ERROR: activation script not found at $STORE_PATH/bin/activate" >&2
    exit 1
  fi

  echo "Activating (requires sudo)..."
  run_sudo "$STORE_PATH/bin/activate"

  echo "Reloading systemd..."
  run_sudo systemctl daemon-reload

  echo "Restarting services..."
  run_sudo systemctl restart kant-pastebin.service 2>/dev/null || true
  run_sudo systemctl restart nora.service 2>/dev/null || true
  run_sudo systemctl restart svg2anim-worker.service 2>/dev/null || true

  echo ""
  echo "=== Verifying ==="
  for svc in kant-pastebin nora nginx svg2anim-worker; do
    if systemctl is-active --quiet "$svc.service" 2>/dev/null; then
      echo "  ✅ $svc.service"
    else
      echo "  ⚠️  $svc.service not active"
    fi
  done
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
