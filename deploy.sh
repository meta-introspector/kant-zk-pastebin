#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PASTEBIN_DIR="${PASTEBIN_DIR:-$SCRIPT_DIR}"
SYSTEM_MANAGER_DIR="${SYSTEM_MANAGER_DIR:-$HOME/projects/system-manager}"

# Parse arguments: deploy or deploy-beta or deploy-beta-host
DEPLOY_TARGET=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)
            DEPLOY_TARGET="$2"
            shift 2
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [[ -z "$DEPLOY_TARGET" ]]; then
    DEPLOY_TARGET="deploy"
fi

# Build the project
log "Building kant-pastebin..."
cd "$PASTEBIN_DIR"
make build

# Commit and push
log "Committing changes..."
git add -A
if ! git diff --quiet; then
    git commit -m "Deploy: $(date -u +%Y-%m-%dT%H:%Z)"
fi

case "$DEPLOY_TARGET" in
    deploy-beta|beta)
        log "Deploying to beta port 8081..."
        # Stop any existing beta service if running
        pkill -f "kant-pastebin-beta" 2>/dev/null || true
        sleep 1
        # Start the beta service using systemctl or directly
        systemctl start kant-pastebin-beta 2>/dev/null || {
            echo "Starting beta service with systemd..."
            systemctl daemon-reload
            systemctl start kant-pastebin-beta
        }
        log "Beta service started on port 8081"
        ;;
    *)
        log "Deploying to server..."
        git push origin "$DEPLOY_TARGET"
        ;;
esac

log "Deployment complete!"
exit 0