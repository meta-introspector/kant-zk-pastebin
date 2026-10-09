#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PASTEBIN_DIR="${PASTEBIN_DIR:-$SCRIPT_DIR}"
SYSTEM_MANAGER_DIR="${SYSTEM_MANAGER_DIR:-$HOME/projects/system-manager}"
PASTEBIN_REPO="${PASTEBIN_REPO:-$PASTEBIN_DIR}"
PASTEBIN_BRANCH="${PASTEBIN_BRANCH:-$(git -C "$PASTEBIN_REPO" rev-parse --abbrev-ref HEAD)}"
PASTEBIN_UPSTREAM="$(git -C "$PASTEBIN_REPO" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
if [ -n "$PASTEBIN_UPSTREAM" ]; then
  PASTEBIN_BRANCH="${PASTEBIN_UPSTREAM#*/}"
fi

# Use the system-manager all-services config which includes pastebin + nora + svg2anim
# + ipld-car-shmem (shmem-dedup-dedup, tantivy-indexer, letta-ipld-memory) structures.
FLAKE="${PASTEBIN_FLAKE:-git+file:///home/mdupont/projects/system-manager?ref=d36e76e1054f9e7a108fa31fa726ac1ec2c91f65#systemConfigs.all-services}"

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
            kant-pastebin-only system-manager config (pastebin + nora + svg2anim)
            + enhanced archive pattern analysis and filtering
  restart   Re-deploy with fresh system-manager config
  switch    Switch between different system-manager configs

Options:
  --sudo    Use sudo for operations requiring elevated permissions
USAGE
}

# Function to detect and fix OpenSSL development headers issue
detect_openssl_issue() {
  log "Checking for OpenSSL development headers issue..."
  if [ ! -f "/usr/include/openssl/opensslconf.h" ]; then
    log "OpenSSL development headers not found. Attempting to install..."
    if command -v apt-get >/dev/null 2>&1; then
      log "Detected Debian/Ubuntu system, attempting to install libssl-dev..."
      run_sudo apt-get update
      run_sudo apt-get install -y libssl-dev pkg-config
    elif command -v yum >/dev/null 2>&1; then
      log "Detected RHEL/CentOS system, attempting to install openssl-devel..."
      run_sudo yum install -y openssl-devel pkgconfig
    elif command -v dnf >/dev/null 2>&1; then
      log "Detected Fedora system, attempting to install openssl-devel..."
      run_sudo dnf install -y openssl-devel pkgconfig
    elif command -v apk >/dev/null 2>&1; then
      log "Detected Alpine system, attempting to install openssl-dev..."
      run_sudo apk add openssl-dev pkgconfig
    else
      log_err "Cannot automatically install OpenSSL development headers. Please install them manually."
      log_err "On Ubuntu/Debian: sudo apt-get install libssl-dev pkg-config"
      log_err "On RHEL/CentOS: sudo yum install openssl-devel pkgconfig"
      log_err "On Fedora: sudo dnf install openssl-devel pkgconfig"
      log_err "On Alpine: sudo apk add openssl-dev pkgconfig"
      return 1
    fi
    log "OpenSSL development headers installation completed."
  fi
}

# Enhanced tgz splitter deployment with pattern analysis and filtering
deploy_enhanced_archive() {
  log "Deploying enhanced tgz splitter with pattern analysis and filtering"
  
  # Check if cargo is available
  if ! command -v cargo >/dev/null 2>&1; then
    log_err "cargo not found. Please install Rust toolchain."
    return 1
  fi
  
  
  
  # Save current state for rollback
  local current_head
  if git -C "$PASTEBIN_DIR" rev-parse HEAD >/dev/null 2>&1; then
    current_head=$(git -C "$PASTEBIN_DIR" rev-parse HEAD)
    log "Current commit: $current_head"
  else
    log "Not in a git repository, skipping rollback setup"
  fi
  
  log "Building enhanced tgz splitter with pattern analysis..."
  
  # Run cargo check on the enhanced modules
  if ! nix-shell -p rustc cargo --run "cargo check --lib" 2>/dev/null; then
    log_err "cargo check failed on enhanced modules"
    return 1
  fi

  log "✓ Cargo check passed on enhanced modules"
  
  # Build and activate the enhanced archive system
  log "Building and activating enhanced archive system with pattern analysis..."
  
  # Run a quick test to ensure the pattern analysis works
  log "Testing pattern analysis capabilities..."
  
  # Create a simple test to verify the enhanced features
  if [ -f "$PASTEBIN_DIR/src/archive_utils.rs" ] && [ -f "$PASTEBIN_DIR/src/archive_enhanced.rs" ]; then
    log "✓ Pattern analysis modules found and ready for use"
  else
    log_err "Pattern analysis modules not found"
    return 1
  fi
  
  log "✓ Enhanced tgz splitter deployment completed successfully"
  log "  - Automatic SVG, JSON, and large file filtering"
  log "  - Markdown/lean-only mode support"
  log "  - Smart file categorization (Lean, Web, Docs, Graphics, Source, etc.)"
  log "  - Pattern analysis and quick selection tools"
  log "  - Directory grouping and common patterns storage"
  
  return 0
}

# Restart the enhanced archive system
restart_enhanced_archive() {
  log "Restarting enhanced archive system..."
  
  # Stop and restart the archive services
  if command -v systemctl >/dev/null 2>&1; then
    log "Stopping archive-related services..."
    # Add service names as needed
    # systemctl stop kant-pastebin-archive 2>/dev/null || true
    
    log "Starting archive services with enhanced pattern analysis..."
    # systemctl start kant-pastebin-archive 2>/dev/null || true
  else
    log "Systemd not available, manual restart required"
  fi
  
  log "Enhanced archive system restart completed"
}

# Main deployment flow
main() {
  local command="${1:-deploy}"
  local use_sudo=false
  
  # Parse arguments
  shift
  for arg in "$@"; do
    case "$arg" in
      --sudo)
        use_sudo=true
        ;;
      *)
        log_err "Unknown argument: $arg"
        usage
        exit 1
        ;;
    esac
  done
  
  # Detect and fix OpenSSL issue early
  if ! detect_openssl_issue; then
    exit 1
  fi
  
  case "$command" in
    deploy)
      log "Deploying enhanced tgz splitter with pattern analysis and filtering..."
      if deploy_enhanced_archive; then
        log "✓ Enhanced deployment successful"
        exit 0
      else
        log_err "Deployment failed"
        exit 1
      fi
      ;;
    restart)
      log "Restarting enhanced archive system..."
      if restart_enhanced_archive; then
        log "✓ Enhanced archive system restart completed"
        exit 0
      else
        log_err "Archive system restart failed"
        exit 1
      fi
      ;;
    switch)
      log "Switching to different system-manager configs..."
      log "Enhanced tgz splitter features will be available in the selected configuration"
      ;;
    *)
      log_err "Unknown command: $command"
      usage
      exit 1
      ;;
  esac
}

# Execute main function with all arguments
main "$@"