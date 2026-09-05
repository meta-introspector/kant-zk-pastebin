#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
WEB_DIR="$SCRIPT_DIR/web"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
SERVER_DIR="$PROJECT_DIR/server"

LOG_DIR="$SCRIPT_DIR/logs"
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
Usage: $0 [pages|worker|all] 

Commands:
  pages      Deploy static frontend to Cloudflare Pages
  worker     Deploy backend Worker to Cloudflare
  all        Deploy both pages and worker
USAGE
}

deploy_pages() {
  log "Deploying static frontend to Cloudflare Pages..."
  cd "$WEB_DIR"
  
  if [ -f "$HOME/.cloudflare" ]; then
    export CLOUDFLARE_API_TOKEN="$(cat "$HOME/.cloudflare" | tr -d '\n')"
  fi
  
  if [ -z "${CLOUDFLARE_API_TOKEN:-}" ]; then
    log_err "CLOUDFLARE_API_TOKEN not set. Skipping Cloudflare Pages deploy."
    return 0
  fi
  
  log "Creating deployment bundle..."
  local tmpdir
  tmpdir="$(mktemp -d)"
  cp -r "$WEB_DIR"/* "$tmpdir/"
  
  log "Deploying to Cloudflare Pages..."
  nix develop -c npx wrangler pages project create kant-zk-pastebin --production-branch main 2>/dev/null || true
  nix develop -c npx wrangler pages deploy "$tmpdir" --project-name kant-zk-pastebin --branch main >> "$LOG_FILE" 2>&1
  
  rm -rf "$tmpdir"
  log "Frontend deployed"
}

deploy_worker() {
  log "Deploying backend Worker to Cloudflare..."
  cd "$SERVER_DIR"
  
  if [ -f "$HOME/.cloudflare" ]; then
    export CLOUDFLARE_API_TOKEN="$(cat "$HOME/.cloudflare" | tr -d '\n')"
  fi
  
  if [ -z "${CLOUDFLARE_API_TOKEN:-}" ]; then
    log_err "CLOUDFLARE_API_TOKEN not set. Skipping Cloudflare Worker deploy."
    return 0
  fi
  
  nix develop -c npx wrangler deploy >> "$LOG_FILE" 2>&1
  log "Backend deployed"
}

deploy_all() {
  log "=== Deploy started ==="
  log "Project: $PROJECT_DIR"
  
  deploy_pages
  deploy_worker
  
  log "=== Deploy complete ==="
}

case "${1:-pages}" in
  pages)
    deploy_pages
    ;;
  worker)
    deploy_worker
    ;;
  all)
    deploy_all
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
