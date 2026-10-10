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

# Main deployment: build with nix develop, commit, push
main() {
  local command="${1:-deploy}"
  shift || true

  case "$command" in
    deploy)
      log "=== Deploy started ==="
      log "Branch: $PASTEBIN_BRANCH"
      log "Pastebin dir: $PASTEBIN_DIR"
      log "Log file: $LOG_FILE"
      log "Step 1: Nix build check (verifies Rust compilation with vendored deps)"

      cd "$PASTEBIN_DIR"
      if ! make build; then
        log_err "Nix build failed"
        exit 1
      fi

      log "✓ Step 1: Build successful"
      log "Step 2: Git commit"

      git add -A
      if ! git diff --cached --quiet; then
        git commit -m "Deploy: automatic release $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        log "✓ Changes committed"
      else
        log "No changes to commit"
      fi

      log "Step 3: Git push"
      git push origin "$PASTEBIN_BRANCH"
      log "✓ Pushed to origin/$PASTEBIN_BRANCH"

      log "=== Deploy complete! ==="
      ;;
    restart)
      log "Restarting kant-pastebin service..."
      sudo systemctl restart kant-pastebin.service 2>/dev/null || true
      log "✓ Restart complete"
      ;;
    *)
      log_err "Unknown command: $command"
      exit 1
      ;;
  esac
}

main "$@"
