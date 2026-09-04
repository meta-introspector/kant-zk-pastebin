#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
SERVER_DIR="$PROJECT_DIR/server"
WEB_DIR="$PROJECT_DIR/web"

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

usage() {
  cat <<USAGE
Usage: $0 [deploy|restart|cf-deploy]

Commands:
  deploy       Full local deploy: git commit, system-manager switch, restart services
  restart      Restart local relay + nginx only
  cf-deploy    Deploy Cloudflare Worker backend only
USAGE
}

deploy_backend() {
  log "Deploying Cloudflare Worker backend..."
  cd "$SERVER_DIR"
  npx wrangler deploy >> "$LOG_FILE" 2>&1
  log "Backend deployed"
}

deploy_frontend() {
  log "Frontend is served from worker assets (wrangler.toml [assets])"
  log "No separate frontend deploy needed"
}

deploy() {
  log "=== Deploy started ==="
  log "Project: $PROJECT_DIR"
  log "Server: $SERVER_DIR"

  log "Step 1: Git commit"
  cd "$PROJECT_DIR"
  git add -A
  git commit -m "deploy: auto-commit before deploy $(date -u +%Y-%m-%dT%H:%M:%SZ)" || true
  log "Local commit verified: $(git rev-parse HEAD)"

  log "Step 2: Deploy Cloudflare Worker"
  deploy_backend
  deploy_frontend

  log "Step 3: System-manager switch"
  cd "$PROJECT_DIR"
  if [ -x "$(command -v system-manager)" ]; then
    log "Running system-manager switch..."
    sudo system-manager switch --flake ~/projects/system-manager >> "$LOG_FILE" 2>&1 || log "WARNING: system-manager switch failed"
  else
    log "system-manager not found, skipping"
  fi

  log "Step 4: Restart services"
  sudo systemctl daemon-reload >> "$LOG_FILE" 2>&1 || true
  sudo systemctl restart kant-zk-relay.service >> "$LOG_FILE" 2>&1 || log "WARNING: kant-zk-relay restart failed"
  sudo systemctl restart nginx.service >> "$LOG_FILE" 2>&1 || log "WARNING: nginx restart failed"

  log "=== Deploy complete ==="
}

restart() {
  log "=== Restart ==="
  sudo systemctl daemon-reload >> "$LOG_FILE" 2>&1 || true
  sudo systemctl restart kant-zk-relay.service >> "$LOG_FILE" 2>&1 || log "WARNING: kant-zk-relay restart failed"
  sudo systemctl restart nginx.service >> "$LOG_FILE" 2>&1 || log "WARNING: nginx restart failed"
  log "=== Restart complete ==="
}

cf_deploy() {
  log "=== Cloudflare Worker deploy ==="
  deploy_backend
  deploy_frontend
  log "=== Cloudflare deploy complete ==="
}

case "${1:-deploy}" in
  deploy)
    deploy
    ;;
  restart)
    restart
    ;;
  cf-deploy)
    cf_deploy
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
