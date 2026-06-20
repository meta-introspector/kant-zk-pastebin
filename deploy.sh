#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PASTEBIN_DIR="${PASTEBIN_DIR:-$SCRIPT_DIR}"
PASTEBIN_REPO="${PASTEBIN_REPO:-$PASTEBIN_DIR}"
PASTEBIN_BRANCH="${PASTEBIN_BRANCH:-$(git -C "$PASTEBIN_REPO" rev-parse --abbrev-ref HEAD)}"
PASTEBIN_UPSTREAM="$(git -C "$PASTEBIN_REPO" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
if [ -n "$PASTEBIN_UPSTREAM" ]; then
  PASTEBIN_BRANCH="${PASTEBIN_UPSTREAM#*/}"
fi
FLAKE="${PASTEBIN_FLAKE:-git+file://${PASTEBIN_REPO}?ref=${PASTEBIN_BRANCH}#systemConfigs.kant-pastebin-only}"
LOG_DIR="${PASTEBIN_DIR}/logs"

run_sudo() {
  if [ "${EUID}" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

usage() {
  cat <<USAGE
Usage: $0 [deploy|restart]

Commands:
  deploy    Build system-manager config, activate it, restart pastebin, then diagnose
  restart   Restart the installed pastebin service, then diagnose
USAGE
}

deploy() {
  cd "$PASTEBIN_DIR"
  mkdir -p "$LOG_DIR"

  echo "Building system-manager configuration: $FLAKE"
  STORE_PATH="$(nix build "$FLAKE" --no-link --json | jq -r '.[0].outputs.out')"
  echo "Built: $STORE_PATH"

  if [ ! -x "$STORE_PATH/bin/activate" ]; then
    echo "ERROR: activation script not found at $STORE_PATH/bin/activate" >&2
    exit 1
  fi

  echo "Activating system-manager configuration"
  run_sudo "$STORE_PATH/bin/activate"
  run_sudo systemctl daemon-reload

  echo "Restarting pastebin application service"
  run_sudo systemctl restart kant-pastebin.service

  "$PASTEBIN_DIR/diagnose.sh"
}

restart_pastebin() {
  run_sudo systemctl restart kant-pastebin.service
  "$PASTEBIN_DIR/diagnose.sh"
}

case "${1:-deploy}" in
  deploy)
    deploy
    ;;
  restart)
    restart_pastebin
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
