#!/usr/bin/env bash
# Complete deployment script for Kant Pastebin
# Installs systemd services, configures nginx, deploys Cloudflare workers

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PASTEBIN_DIR="${SCRIPT_DIR}/.."
LOG_DIR="${PASTEBIN_DIR}/logs"
mkdir -p "$LOG_DIR"

TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
LOG_FILE="${LOG_DIR}/deploy-${TIMESTAMP}.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "[${TIMESTAMP}] ${BLUE}INFO${NC} $1" | tee -a "$LOG_FILE"; }
log_err() { echo -e "[${TIMESTAMP}] ${RED}ERROR${NC} $1" | tee -a "$LOG_FILE" >&2; }
log_success() { echo -e "[${TIMESTAMP}] ${GREEN}SUCCESS${NC} $1" | tee -a "$LOG_FILE"; }
log_warn() { echo -e "[${TIMESTAMP}] ${YELLOW}WARN${NC} $1" | tee -a "$LOG_FILE"; }

run_sudo() {
  if [ "${EUID}" -eq 0 ]; then "$@"; else sudo "$@"; fi
}

# Check if running as root for system operations
check_root() {
  if [ "${EUID}" -ne 0 ]; then
    log_warn "Some operations require sudo. Will prompt for password when needed."
  fi
}

# Deploy systemd services
deploy_systemd() {
  log "=== Deploying systemd services ==="
  
  local services=("kant-pastebin.service" "kant-relay.service")
  
  for service in "${services[@]}"; do
    local src="${PASTEBIN_DIR}/${service}"
    local dst="/etc/systemd/system/${service}"
    
    if [ ! -f "$src" ]; then
      log_err "Service file not found: $src"
      return 1
    fi
    
    log "Installing $service to $dst..."
    run_sudo cp "$src" "$dst"
    run_sudo systemctl daemon-reload
    
    log "Enabling $service..."
    run_sudo systemctl enable "$service"
    
    log "Starting $service..."
    run_sudo systemctl restart "$service"
    
    # Wait and check status
    sleep 2
    if run_sudo systemctl is-active --quiet "$service"; then
      log_success "$service is active"
    else
      log_warn "$service may not be running. Check with: sudo systemctl status $service"
    fi
  done
}

# Deploy nginx configuration
deploy_nginx() {
  log "=== Deploying nginx configuration ==="
  
  local src="${PASTEBIN_DIR}/kant-pastebin.nginx"
  local dst="/etc/nginx/sites-available/kant-pastebin"
  
  if [ ! -f "$src" ]; then
    log_err "Nginx config not found: $src"
    return 1
  fi
  
  log "Installing nginx config..."
  run_sudo cp "$src" "$dst"
  
  # Enable site
  if [ ! -L "/etc/nginx/sites-enabled/kant-pastebin" ]; then
    log "Enabling nginx site..."
    run_sudo ln -sf "$dst" "/etc/nginx/sites-enabled/kant-pastebin"
  fi
  
  # Test nginx config
  log "Testing nginx configuration..."
  if run_sudo nginx -t 2>>"$LOG_FILE"; then
    log_success "Nginx configuration test passed"
  else
    log_err "Nginx configuration test failed"
    return 1
  fi
  
  # Reload nginx
  log "Reloading nginx..."
  run_sudo systemctl reload nginx
  log_success "Nginx reloaded"
}

# Deploy Cloudflare workers using SOPS credentials
deploy_cloudflare() {
  log "=== Deploying Cloudflare Workers ==="
  
  # Check if credentials exist
  local creds_file="${PASTEBIN_DIR}/.sops/credentials.sops.yaml"
  if [ ! -f "$creds_file" ]; then
    log_err "SOPS credentials not found: $creds_file"
    log "Run ./scripts/setup-cloudflare-credentials.sh first"
    return 1
  fi
  
  # Check if credentials have actual values
  local has_token=$(grep -c 'api_token: ""' "$creds_file" || true)
  if [ "$has_token" -eq 0 ]; then
    log "Credentials file appears to have values"
  else
    log_warn "Credentials file has empty values. Run setup-cloudflare-credentials.sh"
  fi
  
  # Run the deploy script
  if [ -f "${PASTEBIN_DIR}/deploy-cloudflare-worker.sh" ]; then
    log "Running Cloudflare worker deployment..."
    cd "$PASTEBIN_DIR"
    ./deploy-cloudflare-worker.sh deploy 2>&1 | tee -a "$LOG_FILE"
  else
    log_err "deploy-cloudflare-worker.sh not found"
    return 1
  fi
}

# Verify deployments
verify() {
  log "=== Verifying Deployments ==="
  
  # Check systemd services
  for service in kant-pastebin.service kant-relay.service; do
    if systemctl is-active --quiet "$service"; then
      log_success "$service: ACTIVE"
    else
      log_warn "$service: NOT RUNNING (sudo systemctl status $service)"
    fi
  done
  
  # Check nginx
  if run_sudo nginx -t 2>/dev/null; then
    log_success "nginx: CONFIG OK"
  else
    log_warn "nginx: CONFIG ISSUE"
  fi
  
  # Check Cloudflare workers
  log "Checking Cloudflare workers..."
  local relay_url="https://kant-zk-relay-wasm.workers.dev/health"
  local pastebin_url="https://kant-zk-pastebin-wasm.workers.dev/health"
  
  for name_url in "relay:$relay_url" "pastebin:$pastebin_url"; do
    local name="${name_url%%:*}"
    local url="${name_url#*:}"
    local status=$(curl -sf -o /dev/null -w "%{http_code}" "$url" 2>>"$LOG_FILE" || echo "000")
    if [ "$status" = "200" ]; then
      log_success "$name worker: healthy ($status)"
    else
      log_warn "$name worker: $status"
    fi
  done
}

# Main
main() {
  log "=== Kant Pastebin Full Deployment ==="
  log "Log file: $LOG_FILE"
  
  check_root
  
  case "${1:-all}" in
    all)
      deploy_systemd
      deploy_nginx
      deploy_cloudflare
      verify
      ;;
    systemd)
      deploy_systemd
      ;;
    nginx)
      deploy_nginx
      ;;
    cloudflare)
      deploy_cloudflare
      ;;
    verify)
      verify
      ;;
    *)
      echo "Usage: $0 [all|systemd|nginx|cloudflare|verify]"
      exit 1
      ;;
  esac
  
  log "=== Deployment Complete ==="
}

main "$@"
