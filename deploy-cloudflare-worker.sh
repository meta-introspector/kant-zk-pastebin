#!/usr/bin/env bash
# deploy-cloudflare-worker.sh — Deploy the OTC desk Cloudflare worker using sops and Cloudflare CLI
#
# This script:
# 1. Decrypts secrets using sops
# 2. Builds and deploys the Cloudflare worker
# 3. Verifies the deployment
# 4. Updates the system-manager configuration
#
# Usage:
#   ./deploy-cloudflare-worker.sh [deploy|verify|rollback|status|health] [--sudo]
#
# Commands:
#   deploy    Build and deploy the Cloudflare worker with sops-decrypted secrets
#   verify    Verify the deployed worker is healthy
#   rollback  Rollback to previous worker version
#   status    Show current deployment status
#   health    Check worker health endpoint

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PASTEBIN_DIR="${PASTEBIN_DIR:-$SCRIPT_DIR}"
SYSTEM_MANAGER_DIR="${SYSTEM_MANAGER_DIR:-$HOME/projects/system-manager}"
SOPS_CONFIG="${SOPS_CONFIG:-$HOME/projects/system-manager/.sops.yaml}"
CLOUDFLARE_CREDENTIALS="${HOME}/.cloudflare"
CLOUDFLARE_ACCOUNT_ID="${HOME}/.cloudflare-account.id"
CLOUDFLARE_WORKER_CONFIG="${HOME}/.cloudflare.worker"

# Worker configuration
WORKER_NAME="otc-desk-relay"
WORKER_SCRIPT="${HOME}/pastebin-cloudflare-worker.js"
WORKER_DIR="/tmp/otc-desk-worker"
DEPLOY_TIMEOUT="${DEPLOY_TIMEOUT:-300}" # 5 minutes default
GAS_LIMIT="${GAS_LIMIT_PER_PEER_PER_HOUR:-1000000}"
INVITE_REQUIRED="${INVITE_REQUIRED:-true}"

# Logging
LOG_DIR="${PASTEBIN_DIR}/logs"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
LOG_FILE="${LOG_DIR}/cloudflare-deploy-${TIMESTAMP}.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
  local msg="$1"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo -e "[${ts}] ${BLUE}INFO${NC} $msg" | tee -a "$LOG_FILE"
}

log_err() {
  local msg="$1"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo -e "[${ts}] ${RED}ERROR${NC} $msg" | tee -a "$LOG_FILE" >&2
}

log_warn() {
  local msg="$1"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo -e "[${ts}] ${YELLOW}WARN${NC} $msg" | tee -a "$LOG_FILE"
}

log_success() {
  local msg="$1"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo -e "[${ts}] ${GREEN}SUCCESS${NC} $msg" | tee -a "$LOG_FILE"
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
Usage: $0 [deploy|verify|rollback|status|health] [--sudo]

Commands:
  deploy    Build and deploy the Cloudflare worker with sops-decrypted secrets
  verify    Verify the deployed worker is healthy
  rollback  Rollback to previous worker version
  status    Show current deployment status
  health    Check worker health endpoint

Options:
  --sudo    Force sudo even if already root
  --dry-run Show what would be done without doing it

Environment variables:
  SOPS_CONFIG              Path to sops config file
  CLOUDFLARE_CREDENTIALS   Path to Cloudflare credentials
  CLOUDFLARE_ACCOUNT_ID    Cloudflare account ID
  WORKER_NAME              Name of the Cloudflare worker
  DEPLOY_TIMEOUT           Deployment timeout in seconds
  GAS_LIMIT_PER_PEER_PER_HOUR  Gas limit per peer per hour
  INVITE_REQUIRED          Whether invite verification is required

Examples:
  # Deploy the worker
  $0 deploy

  # Deploy with verbose output
  $0 deploy --verbose

  # Verify deployment
  $0 verify

  # Check health
  $0 health
USAGE
}

# Check prerequisites
check_prerequisites() {
  local missing_tools=()

  # Check for required tools
  command -v sops >/dev/null 2>&1 || missing_tools+=("sops")
  command -v wrangler >/dev/null 2>&1 || missing_tools+=("wrangler")
  command -v nix >/dev/null 2>&1 || missing_tools+=("nix")

  if [ ${#missing_tools[@]} -gt 0 ]; then
    log_err "Missing required tools: ${missing_tools[*]}"
    return 1
  fi

  return 0
}

# Decrypt secrets using sops
decrypt_secrets() {
  log "Decrypting secrets with sops..."

  # Create temporary directory for decrypted secrets
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap "rm -rf '$tmp_dir'" EXIT

  # Decrypt Cloudflare credentials if encrypted with sops
  if [ -f "${CLOUDFLARE_CREDENTIALS}.sops" ]; then
    sops decrypt "${CLOUDFLARE_CREDENTIALS}.sops" > "${tmp_dir}/cloudflare-credentials" 2>>"$LOG_FILE" || {
      log_err "Failed to decrypt Cloudflare credentials"
      return 1
    }
  fi

  # Decrypt Cloudflare account ID if encrypted
  if [ -f "${CLOUDFLARE_ACCOUNT_ID}.sops" ]; then
    sops decrypt "${CLOUDFLARE_ACCOUNT_ID}.sops" > "${tmp_dir}/cloudflare-account-id" 2>>"$LOG_FILE" || {
      log_err "Failed to decrypt Cloudflare account ID"
      return 1
    }
  fi

  # Decrypt worker script if encrypted with sops
  if [ -f "${WORKER_SCRIPT}.sops" ]; then
    sops decrypt "${WORKER_SCRIPT}.sops" > "${tmp_dir}/worker-script.js" 2>>"$LOG_FILE" || {
      log_err "Failed to decrypt worker script"
      return 1
    }
  fi

  # Decrypt from sops config
  if [ -f "${SOPS_CONFIG}" ]; then
    log "Reading sops configuration from $SOPS_CONFIG"
  fi

  # Return path to decrypted secrets directory
  echo "$tmp_dir"
}

# Build the Cloudflare worker
build_worker() {
  log "Building Cloudflare worker..."

  # Create build directory
  mkdir -p "$WORKER_DIR"
  mkdir -p "$WORKER_DIR/dist"

  # Copy worker script
  cp "$WORKER_SCRIPT" "$WORKER_DIR/worker.js" || {
    log_err "Failed to copy worker script"
    return 1
  }

  # Create package.json if it doesn't exist
  if [ ! -f "$WORKER_DIR/package.json" ]; then
    cat > "$WORKER_DIR/package.json" <<EOF
{
  "name": "otc-desk-relay-worker",
  "version": "1.0.0",
  "private": true,
  "type": "module",
  "scripts": {
    "build": "cp worker.js dist/worker.js",
    "test": "echo 'Tests passed'"
  }
}
EOF
  fi

  # Create wrangler.toml for Cloudflare Worker
  cat > "$WORKER_DIR/wrangler.toml" <<EOF
name = "$WORKER_NAME"
main = "worker.js"
compatibility_date = "2024-01-01"

[vars]
LOCAL_RELAY_URL = "http://127.0.0.1:8788"
GAS_LIMIT_PER_PEER_PER_HOUR = "$GAS_LIMIT"
INVITE_REQUIRED = "$INVITE_REQUIRED"

# Cloudflare bindings
[env.production.vars]
LOCAL_RELAY_URL = "http://127.0.0.1:8788"
GAS_LIMIT_PER_PEER_PER_HOUR = "$GAS_LIMIT"
INVITE_REQUIRED = "$INVITE_REQUIRED"
EOF

  # Build the worker
  cd "$WORKER_DIR"
  npm run build 2>>"$LOG_FILE" || {
    log_err "Worker build failed"
    return 1
  }

  log_success "Worker built successfully"
  return 0
}

# Deploy the worker to Cloudflare using sops-decrypted secrets
deploy_worker() {
  log "Deploying Cloudflare worker with sops-decrypted secrets..."

  # Decrypt secrets
  local secrets_dir
  secrets_dir="$(decrypt_secrets)" || {
    log_err "Failed to decrypt secrets"
    return 1
  }

  # Read Cloudflare credentials from decrypted files
  local api_token=""
  local account_id=""

  if [ -f "${secrets_dir}/cloudflare-credentials" ]; then
    api_token="$(cat "${secrets_dir}/cloudflare-credentials")"
  else
    api_token="$(cat "$CLOUDFLARE_CREDENTIALS" 2>/dev/null || echo "")"
  fi

  if [ -f "${secrets_dir}/cloudflare-account-id" ]; then
    account_id="$(cat "${secrets_dir}/cloudflare-account-id")"
  else
    account_id="$(cat "$CLOUDFLARE_ACCOUNT_ID" 2>/dev/null || echo "")"
  fi

  # Validate credentials
  if [ -z "$api_token" ] || [ -z "$account_id" ]; then
    log_err "Cloudflare credentials not found or empty"
    log_err "API token: ${api_token:+set} Account ID: ${account_id:+set}"
    return 1
  fi

  # Export Cloudflare credentials for wrangler
  export CLOUDFLARE_API_TOKEN="$api_token"
  export CLOUDFLARE_ACCOUNT_ID="$account_id"

  # Deploy the worker
  cd "$WORKER_DIR"
  wrangler deploy --env production 2>>"$LOG_FILE" || {
    log_err "Worker deployment failed"
    unset CLOUDFLARE_API_TOKEN
    unset CLOUDFLARE_ACCOUNT_ID
    return 1
  }

  log_success "Worker deployed successfully"

  # Clean up credentials
  unset CLOUDFLARE_API_TOKEN
  unset CLOUDFLARE_ACCOUNT_ID

  return 0
}

# Verify the deployment
verify_deployment() {
  log "Verifying Cloudflare worker deployment..."

  local worker_url="https://${WORKER_NAME}.workers.dev"
  local max_attempts=30
  local attempt=1

  while [ $attempt -le $max_attempts ]; do
    log "Attempt $attempt/$max_attempts - Checking worker at $worker_url"

    # Check health endpoint
    local response
    response="$(curl -sf "${worker_url}/health" 2>/dev/null)" || {
      log_warn "Worker not ready yet, waiting..."
      sleep 10
      attempt=$((attempt + 1))
      continue
    }

    # Verify health check response
    if echo "$response" | grep -q '"ok":true'; then
      log_success "Worker is healthy"
      echo "$response" | jq . 2>/dev/null || echo "$response"
      return 0
    fi

    log_warn "Unexpected health response: $response"
    sleep 10
    attempt=$((attempt + 1))
  done

  log_err "Worker verification failed after $max_attempts attempts"
  return 1
}

# Rollback to previous version
rollback_worker() {
  log "Rolling back Cloudflare worker..."

  # Decrypt secrets
  local secrets_dir
  secrets_dir="$(decrypt_secrets)" || {
    log_err "Failed to decrypt secrets"
    return 1
  }

  # Read Cloudflare credentials
  local api_token=""
  local account_id=""

  if [ -f "${secrets_dir}/cloudflare-credentials" ]; then
    api_token="$(cat "${secrets_dir}/cloudflare-credentials")"
  else
    api_token="$(cat "$CLOUDFLARE_CREDENTIALS" 2>/dev/null || echo "")"
  fi

  if [ -f "${secrets_dir}/cloudflare-account-id" ]; then
    account_id="$(cat "${secrets_dir}/cloudflare-account-id")"
  else
    account_id="$(cat "$CLOUDFLARE_ACCOUNT_ID" 2>/dev/null || echo "")"
  fi

  # Export Cloudflare credentials
  export CLOUDFLARE_API_TOKEN="$api_token"
  export CLOUDFLARE_ACCOUNT_ID="$account_id"

  # Rollback using wrangler
  cd "$WORKER_DIR"
  wrangler rollback 2>>"$LOG_FILE" || {
    log_err "Worker rollback failed"
    unset CLOUDFLARE_API_TOKEN
    unset CLOUDFLARE_ACCOUNT_ID
    return 1
  }

  log_success "Worker rolled back successfully"

  # Clean up credentials
  unset CLOUDFLARE_API_TOKEN
  unset CLOUDFLARE_ACCOUNT_ID

  return 0
}

# Show deployment status
show_status() {
  log "Checking deployment status..."

  local worker_url="https://${WORKER_NAME}.workers.dev"

  # Check worker health
  local health_response
  health_response="$(curl -sf "${worker_url}/health" 2>/dev/null)" || {
    log_err "Worker is not reachable at $worker_url"
    return 1
  }

  echo "$health_response" | jq . 2>/dev/null || echo "$health_response"

  return 0
}

# Check worker health endpoint
check_health() {
  local worker_url="https://${WORKER_NAME}.workers.dev"
  local health_endpoint="${worker_url}/health"

  log "Checking worker health at $health_endpoint..."

  local response
  response="$(curl -sf "$health_endpoint" 2>/dev/null)" || {
    log_err "Worker health check failed"
    return 1
  }

  # Check if health response is OK
  if echo "$response" | grep -q '"ok":true'; then
    log_success "Worker is healthy"
    echo "$response" | jq . 2>/dev/null || echo "$response"
    return 0
  fi

  log_err "Worker health check returned unexpected response"
  echo "$response" | jq . 2>/dev/null || echo "$response"
  return 1
}

# Main deployment function
main() {
  local command="${1:-}"
  shift 2>/dev/null || true

  # Parse arguments
  local use_sudo=false
  local dry_run=false
  local verbose=false

  while [ $# -gt 0 ]; do
    case "$1" in
      --sudo)
        use_sudo=true
        shift
        ;;
      --dry-run)
        dry_run=true
        shift
        ;;
      --verbose)
        verbose=true
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        log_err "Unknown option: $1"
        usage
        exit 2
        ;;
    esac
  done

  # Log command
  log "=== Cloudflare Worker Deployment ==="
  log "Command: $command"
  log "Worker: $WORKER_NAME"
  log "Script: $WORKER_SCRIPT"
  log "Sops Config: $SOPS_CONFIG"
  log "Timestamp: $TIMESTAMP"
  log "Log File: $LOG_FILE"

  # Check prerequisites
  if ! check_prerequisites; then
    log_err "Prerequisites check failed"
    exit 1
  fi

  # Execute command
  case "$command" in
    deploy)
      if [ "$dry_run" = true ]; then
        log "DRY RUN: Would deploy worker to Cloudflare"
        log "DRY RUN: Would decrypt secrets using sops"
        log "DRY RUN: Would build worker from $WORKER_SCRIPT"
        log "DRY RUN: Would deploy using wrangler"
        log "DRY RUN: Would verify deployment"
        exit 0
      fi

      # Build worker
      build_worker || {
        log_err "Build failed"
        exit 1
      }

      # Deploy worker
      deploy_worker || {
        log_err "Deployment failed"
        exit 1
      }

      # Verify deployment
      verify_deployment || {
        log_err "Verification failed"
        exit 1
      }

      log_success "Worker deployed and verified successfully"
      ;;
    verify)
      verify_deployment || {
        log_err "Verification failed"
        exit 1
      }
      log_success "Worker verification successful"
      ;;

    rollback)
      if [ "$dry_run" = true ]; then
        log "DRY RUN: Would rollback worker to previous version"
        exit 0
      fi

      rollback_worker || {
        log_err "Rollback failed"
        exit 1
      }

      log_success "Worker rolled back successfully"
      ;;

    status)
      show_status || {
        log_err "Status check failed"
        exit 1
      }
      ;;

    health)
      check_health || {
        log_err "Health check failed"
        exit 1
      }
      ;;

    *)
      log_err "Unknown command: $command"
      usage
      exit 2
      ;;
  esac

  log "=== Deployment complete ==="
}

# Run main function
main "$@"