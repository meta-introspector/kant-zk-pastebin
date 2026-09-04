#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_DIR="$SCRIPT_DIR"
SERVER_DIR="$PROJECT_DIR/server"
WEB_DIR="$PROJECT_DIR/web"
SYSTEM_MANAGER_DIR="$HOME/projects/system-manager"

LOG_DIR="$PROJECT_DIR/logs"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
LOG_FILE="${LOG_DIR}/deploy-${TIMESTAMP}.log"

mkdir -p "$LOG_DIR"

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
Usage: $0 [deploy|restart|switch]

Commands:
  deploy    Full deploy: git commit, system-manager switch, restart services
  restart   Restart relay + nginx only
  switch    Build + activate system-manager config with sudo
USAGE
}

deploy() {
  log "=== Deploy started ==="
  log "Project: $PROJECT_DIR"

  log "Step 1: Git commit"
  cd "$PROJECT_DIR"
  git add -A
  git commit -m "deploy: auto-commit before deploy $(date -u +%Y-%m-%dT%H:%M:%SZ)" || true
  log "Local commit verified: $(git rev-parse HEAD)"

  log "Step 2: System-manager switch"
  switch_system_manager

  log "Step 3: Restart services"
  run_sudo systemctl daemon-reload >> "$LOG_FILE" 2>&1 || true
  run_sudo systemctl restart kant-zk-relay.service >> "$LOG_FILE" 2>&1 || log "WARNING: kant-zk-relay restart failed"
  run_sudo systemctl restart nginx.service >> "$LOG_FILE" 2>&1 || log "WARNING: nginx restart failed"

  log "Step 4: Verify"
  verify

  log "=== Deploy complete ==="
}

switch_system_manager() {
  log "Building system-manager config..."
  cd "$SYSTEM_MANAGER_DIR"
  
  STORE_PATH="$(nix build --impure .#systemConfigs.all-services --no-link --json 2>>"$LOG_FILE" | jq -r '.[0].outputs.out')" || {
    log_err "system-manager config build failed"
    exit 1
  }
  log "Built: $STORE_PATH"

  if [ ! -x "$STORE_PATH/bin/activate" ]; then
    log_err "activation script not found at $STORE_PATH/bin/activate"
    exit 1
  fi

  log "Activating (requires sudo)..."
  run_sudo "$STORE_PATH/bin/activate" >> "$LOG_FILE" 2>&1 || {
    log_err "system-manager activation failed"
    exit 1
  }
  log "Activation OK"
}

restart() {
  log "=== Restart ==="
  run_sudo systemctl daemon-reload >> "$LOG_FILE" 2>&1 || true
  run_sudo systemctl restart kant-zk-relay.service >> "$LOG_FILE" 2>&1 || log "WARNING: kant-zk-relay restart failed"
  run_sudo systemctl restart nginx.service >> "$LOG_FILE" 2>&1 || log "WARNING: nginx restart failed"
  verify
  log "=== Restart complete ==="
}

verify() {
  log "Verifying services..."
  for svc in kant-zk-relay nginx; do
    if run_sudo systemctl is-active --quiet "$svc.service" 2>/dev/null; then
      log "  ✅ $svc.service"
    else
      log "  ⚠️  $svc.service not active"
    fi
  done

  log "Verifying relay endpoint..."
  if curl -sf http://127.0.0.1:8787/health > /dev/null 2>&1; then
    log "  ✅ Relay health: $(curl -s http://127.0.0.1:8787/health)"
  else
    log "  ⚠️  Relay not responding on 8787"
  fi
}

case "${1:-deploy}" in
  deploy)
    deploy
    ;;
  restart)
    restart
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
