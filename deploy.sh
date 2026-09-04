#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
SERVER_DIR="$PROJECT_DIR/server"

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
Usage: $0 [deploy|restart] 

Commands:
  deploy    Deploy frontend + backend to Cloudflare Workers
  restart   Redeploy backend worker only
USAGE
}

deploy_backend() {
  log "Deploying backend worker..."
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

  deploy_backend
  deploy_frontend

  log "=== Deploy complete ==="
}

restart() {
  log "=== Restart ==="
  deploy_backend
  log "=== Restart complete ==="
}

case "${1:-deploy}" in
  deploy)
    deploy
    ;;
  restart)
    restart
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
