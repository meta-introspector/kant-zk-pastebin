#!/usr/bin/env bash
# deploy-cloudflare-worker.sh — Deploy Cloudflare Workers for kant-zk-pastebin
#
# Deploys two workers:
#   1. kant-zk-relay-wasm — Lean WASM relay (Durable Objects)
#   2. kant-zk-pastebin-wasm — Rust-in-WASM pastebin tool
#
# Usage:
#   ./deploy-cloudflare-worker.sh deploy
#   ./deploy-cloudflare-worker.sh verify
#   ./deploy-cloudflare-worker.sh status

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PASTEBIN_DIR="${PASTEBIN_DIR:-$SCRIPT_DIR}"

LOG_DIR="${PASTEBIN_DIR}/logs"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
LOG_FILE="${LOG_DIR}/cloudflare-deploy-${TIMESTAMP}.log"

# Colors
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

check_prerequisites() {
  local missing=()
  command -v sops >/dev/null 2>&1 || missing+=("sops")
  command -v wrangler >/dev/null 2>&1 || missing+=("wrangler")
  command -v nix >/dev/null 2>&1 || missing+=("nix")
  if [ ${#missing[@]} -gt 0 ]; then
    log_err "Missing required tools: ${missing[*]}"
    return 1
  fi
  return 0
}

decrypt_secrets() {
  log "Decrypting secrets with sops..."
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap "rm -rf '$tmp_dir'" EXIT

  # Decrypt Cloudflare credentials
  if [ -f "${PASTEBIN_DIR}/.sops/credentials.sops.yaml" ]; then
    sops decrypt "${PASTEBIN_DIR}/.sops/credentials.sops.yaml" > "${tmp_dir}/creds.yaml" 2>>"$LOG_FILE" || {
      log_err "Failed to decrypt credentials"
      return 1
    }
    log "Secrets decrypted to ${tmp_dir}/creds.yaml"
  else
    log_warn "No .sops/credentials.sops.yaml found, using env vars"
  fi

  export CF_API_TOKEN="${CF_API_TOKEN:-$(grep api_token "${tmp_dir}/creds.yaml" 2>/dev/null | awk '{print $2}' | tr -d '"')}"
  export CF_ACCOUNT_ID="${CF_ACCOUNT_ID:-$(grep account_id "${tmp_dir}/creds.yaml" 2>/dev/null | awk '{print $2}' | tr -d '"')}"

  if [ -z "$CF_API_TOKEN" ]; then
    log_err "CF_API_TOKEN not set and not found in decrypted secrets"
    return 1
  fi
  if [ -z "$CF_ACCOUNT_ID" ]; then
    log_err "CF_ACCOUNT_ID not set and not found in decrypted secrets"
    return 1
  fi

  log "Cloudflare credentials loaded"
}

deploy_worker() {
  local name="$1"
  local script="$2"
  local env_file="$3"

  log "Deploying worker: ${name}..."

  # Build wrangler.toml with correct KV namespace
  local tmp_wrangler
  tmp_wrangler="$(mktemp)"
  trap "rm -f '$tmp_wrangler'" EXIT

  # Copy and configure wrangler.toml
  cp "${PASTEBIN_DIR}/server/wrangler.toml" "$tmp_wrangler"

  # Generate kv-namespaces from env
  if [ -n "${KV_NAMESPACE_ID:-}" ]; then
    sed -i "s/your-kv-namespace-id/${KV_NAMESPACE_ID}/g" "$tmp_wrangler"
  fi

  cd "$tmp_wrangler"

  # Login to Cloudflare
  if ! wrangler whoami >/dev/null 2>&1; then
    log "Authenticating with Cloudflare..."
    if [ -n "${CF_API_TOKEN}" ]; then
      echo "${CF_API_TOKEN}" | wrangler login 2>/dev/null || {
        # Try alternative: set token directly
        export CLOUDFLARE_API_TOKEN="${CF_API_TOKEN}"
      }
    fi
  fi

  # Deploy
  log "Running wrangler deploy for ${name}..."
  wrangler deploy --name "${name}" --env "$env_file" 2>>"$LOG_FILE" || {
    log_err "Wrangler deploy failed for ${name}"
    return 1
  }

  log_success "Worker ${name} deployed"
}

deploy_rust_wasm_pastebin() {
  log "=== Deploying Rust WASM Pastebin Worker ==="

  # Step 1: Build Rust to WASM
  log "Step 1: Building Rust to WASM..."
  rustup target add wasm32-unknown-unknown 2>/dev/null || true

  cd "${PASTEBIN_DIR}"
  mkdir -p target/wasm32-unknown-unknown/release

  # Build with wasm-bindgen for JS interop
  CARGO_TARGET="target/wasm32-unknown-unknown/release" \
    cargo build --target wasm32-unknown-unknown --release --bin kant-pastebin 2>&1 | tee -a "$LOG_FILE" || {
    log_err "Rust WASM build failed"
    return 1
  }

  # Convert to wasm32-unknown-unknown if needed
  local wasm_file="target/wasm32-unknown-unknown/release/kant_pastebin.wasm"

  # Step 2: Publish WASM binary to Nora
  log "Step 2: Publishing WASM binary to Nora..."
  mkdir -p /mnt/data1/kant/wasm-pastebin
  cp "$wasm_file" /mnt/data1/kant/wasm-pastebin/kant-pastebin.wasm

  # Step 3: Create Cloudflare Worker that loads and uses the WASM
  local worker_dir="$(mktemp -d)"
  trap "rm -rf '$worker_dir'" EXIT

  cp "${PASTEBIN_DIR}/server/wasm-pastebin-worker.mjs" "$worker_dir/worker.mjs"

  # Copy WASM to worker dir
  cp /mnt/data1/kant/wasm-pastebin/kant-pastebin.wasm "$worker_dir/"

  cd "$worker_dir"
  npm init -y >/dev/null 2>&1
  npm install --save-dev wrangler 2>&1 | tail -1 | tee -a "$LOG_FILE"

  # Build wrangler.toml
  cat > wrangler.toml <<EOF
name = "kant-zk-pastebin-wasm"
main = "worker.mjs"
compatibility_date = "2025-01-01"

[assets]
directory = "."
binding = "ASSETS"
EOF

  # Step 4: Deploy via wrangler
  log "Step 4: Deploying Cloudflare Worker..."
  wrangler login 2>/dev/null || true
  wrangler deploy --name kant-zk-pastebin-wasm 2>>"$LOG_FILE" || {
    log_err "Failed to deploy Rust WASM pastebin worker"
    return 1
  }

  log_success "Rust WASM Pastebin Worker deployed at https://kant-zk-pastebin-wasm.workers.dev"
}

deploy_lean_wasm_relay() {
  log "=== Deploying Lean WASM Relay Worker ==="

  # Step 0: Stamp the commit so /health can name the build being served.
  local commit
  commit="$(git -C "${PASTEBIN_DIR}" rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"
  log "Deploying commit: ${commit}"

  # Step 1: Build Lean to WASM
  log "Step 1: Building Lean kernel to WASM..."
  cd /home/mdupont/projects/pastebin-lean
  lake exe emitwasm dist 2>&1 | tee -a "$LOG_FILE" || {
    log_err "Lean WASM build failed"
    return 1
  }

  # Verify WASM
  if [ ! -f dist/kant_kernel.wasm ]; then
    log_err "WASM binary not found at dist/kant_kernel.wasm"
    return 1
  fi

  # Step 2: Publish WASM binary to Nora
  log "Step 2: Publishing Lean WASM binary..."
  mkdir -p /mnt/data1/kant/wasm-lean-relay
  cp /home/mdupont/projects/pastebin-lean/dist/kant_kernel.wasm /mnt/data1/kant/wasm-lean-relay/
  cp /home/mdupont/projects/pastebin-lean/dist/kernel-vectors.json /mnt/data1/kant/wasm-lean-relay/

  # Step 3: Create Cloudflare Worker with WASM
  local worker_dir="$(mktemp -d)"
  trap "rm -rf '$worker_dir'" EXIT

  # The checked-in worker.js is the real relay (server/wrangler.toml points
  # at it). Stamp the commit placeholder so the deployed Worker answers
  # /health with the build it is serving.
  cp "${PASTEBIN_DIR}/server/worker.js" "$worker_dir/worker.js"
  sed -i "s|__KANT_COMMIT__|${commit}|g" "$worker_dir/worker.js"
  # Ship the same web/ tree the systemd twin serves, so the wasm core,
  # the JS CID reference and p2p.html cannot drift apart.
  cp -r "${PASTEBIN_DIR}/web" "$worker_dir/web"

  cat > "$worker_dir/wrangler.toml" <<EOF
name = "kant-zk-relay-wasm"
main = "worker.js"
compatibility_date = "2025-01-01"

[[durable_objects.bindings]]
name = "ROOMS"
class_name = "Room"

[[migrations]]
tag = "v1"
new_sqlite_classes = ["Room"]

[assets]
directory = "./web"
binding = "ASSETS"
EOF

  cd "$worker_dir"

  # Create package.json
  cat > package.json <<EOF
{
  "name": "kant-zk-relay-wasm",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "dev": "wrangler dev",
    "deploy": "wrangler deploy",
    "tail": "wrangler tail"
  },
  "devDependencies": {
    "wrangler": "latest"
  }
}
EOF

  log "Step 4: Deploying Cloudflare Worker..."
  wrangler login 2>/dev/null || true
  wrangler deploy --name kant-zk-relay-wasm 2>>"$LOG_FILE" || {
    log_err "Failed to deploy Lean WASM relay worker"
    return 1
  }

  log_success "Lean WASM Relay Worker deployed at https://kant-zk-relay-wasm.workers.dev"
}

deploy() {
  log "=== Cloudflare Worker Deployment ==="
  log "Pastebin dir: $PASTEBIN_DIR"
  log "Log file: $LOG_FILE"

  mkdir -p "$LOG_DIR"

  if ! check_prerequisites; then
    log_err "Prerequisites not met"
    exit 1
  fi

  decrypt_secrets || {
    log_err "Failed to decrypt secrets"
    exit 1
  }

  deploy_lean_wasm_relay || {
    log_err "Lean WASM relay deployment failed"
    exit 1
  }

  deploy_rust_wasm_pastebin || {
    log_err "Rust WASM pastebin deployment failed"
    exit 1
  }

  log_success "=== All Cloudflare Workers Deployed ==="
}

verify() {
  log "=== Verifying the twin trio ==="

  # The deployed Worker lives on the kant account (purple-fire-b881), not
  # the default jmikedupont2 subdomain — see docs/WASM_P2P_AND_CI_2026-10-01.md.
  local relay_url="https://kant-zk-relay-wasm.purple-fire-b881.workers.dev/health"
  local systemd_url="${KANT_SYSTEMD_RELAY:-http://127.0.0.1:8796}/health"

  local head systemd_head
  head="$(curl -sf "$relay_url" 2>>"$LOG_FILE" || echo '{}')"
  systemd_head="$(curl -sf "$systemd_url" 2>>"$LOG_FILE" || echo '{}')"
  log "cloudflare : ${head}"
  log "systemd    : ${systemd_head}"

  local cf_commit sys_commit
  cf_commit=$(echo "$head" | grep -o '"commit":"[^"]*"' | cut -d'"' -f4)
  sys_commit=$(echo "$systemd_head" | grep -o '"commit":"[^"]*"' | cut -d'"' -f4)

  if [ -z "$cf_commit" ]; then
    log_warn "cloudflare twin reports no commit (stale deploy?)"
  elif [ -z "$sys_commit" ]; then
    log_warn "systemd twin reports no commit"
  elif [ "$cf_commit" != "$sys_commit" ]; then
    log_warn "TWIN DRIFT: cloudflare=${cf_commit} systemd=${sys_commit}"
  else
    log_success "both twins serve ${cf_commit}"
  fi

  # The wasm core is the shared artifact: same bytes on both legs, or peers
  # on different twins compute different CIDs.
  local cf_wasm sys_wasm
  cf_wasm=$(curl -sf "${relay_url%/health}/pastebin_wasm_bg.wasm" 2>>"$LOG_FILE" | sha256sum | cut -d' ' -f1)
  sys_wasm=$(curl -sf "${systemd_url%/health}/pastebin_wasm_bg.wasm" 2>>"$LOG_FILE" | sha256sum | cut -d' ' -f1)
  if [ -n "$cf_wasm" ] && [ "$cf_wasm" = "$sys_wasm" ]; then
    log_success "wasm core identical on both twins (${cf_wasm:0:12})"
  else
    log_warn "WASM DRIFT: cloudflare=${cf_wasm:0:12} systemd=${sys_wasm:0:12} — redeploy the stale leg"
  fi
}

status() {
  log "=== Worker Status ==="
  wrangler whoami 2>/dev/null | tee -a "$LOG_FILE" || true

  local workers
  workers=$(wrangler list 2>/dev/null | tee -a "$LOG_FILE") || true
  echo "$workers" | grep -E "kant-zk" || true
}

case "${1:-deploy}" in
  deploy)
    deploy
    ;;
  verify)
    verify
    ;;
  status)
    status
    ;;
  *)
    cat <<EOF
Usage: $0 [deploy|verify|status]

Commands:
  deploy    Deploy all Cloudflare Workers (Lean WASM relay + Rust WASM pastebin)
  verify    Check health of deployed workers
  status    Show deployment status
EOF
    exit 2
    ;;
esac
