#!/usr/bin/env bash
set -euo pipefail

PASTEBIN_DIR="${PASTEBIN_DIR:-/home/mdupont/pastebin}"
FLAKE="${PASTEBIN_FLAKE:-${PASTEBIN_DIR}#systemConfigs.kant-pastebin-only}"
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
