#!/usr/bin/env bash
# deploy.sh — one-shot deploy of the kant-zk stack: local services + Cloudflare twins.
#
# Usage:
#   scripts/deploy.sh all        # everything below (default)
#   scripts/deploy.sh local      # build/restart local systemd services only
#   scripts/deploy.sh cf         # deploy Cloudflare worker + pages only
#   scripts/deploy.sh status     # show health of local services + CF endpoints
#   scripts/deploy.sh check      # preflight: tools, tokens, dirs
#
# The systemd publisher service (kant-zk-publisher) also self-deploys to
# Cloudflare on its 5-minute cycle: pages every cycle, worker when
# worker.js changes. This script is the manual/one-shot path.
set -euo pipefail
cd "$(dirname "$0")/.."

NODE=/nix/store/2bslrww4ch7my47xxwabj1qy4acq4720-nodejs-slim-24.14.1/bin/node
PROFILE_BIN=/home/mdupont/.nix-profile/bin
CF_TOKEN_FILE="$HOME/.cloudflare"
WORKER_NAME=kant-zk-relay
WORKER_URL="https://${WORKER_NAME}.jmikedupont2.workers.dev"
PAGES_URL="https://kant-zk-pastebin.pages.dev"
RELAY_LOCAL_URL="https://solana.solfunmeme.com/relay"

info()  { printf '\033[32m[deploy]\033[0m %s\n' "$*"; }
warn()  { printf '\033[33m[deploy]\033[0m %s\n' "$*"; }
die()   { printf '\033[31m[deploy] FAIL:\033[0m %s\n' "$*" >&2; exit 1; }

preflight() {
  command -v systemctl >/dev/null || die "systemctl not found"
  [ -x "$NODE" ] || die "node not at $NODE"
  [ -f "$CF_TOKEN_FILE" ] || die "no Cloudflare token at $CF_TOKEN_FILE"
  [ -f "$PROFILE_BIN/npx" ] || die "no npx at $PROFILE_BIN"
  [ -d /var/lib/kant-zk/rooms ] || die "no rooms dir"
  info "preflight ok"
}

local_services() {
  info "restarting local services…"
  sudo systemctl restart kant-relay.service kant-zk-archive.service
  # forward runs in self-maintaining rooms mode: it watches /var/lib/kant-zk/rooms
  sudo systemctl restart kant-zk-forward.service
  # publisher deploys CF itself on cycle; restart to pick up code changes
  sudo systemctl restart kant-zk-publisher.service
  sleep 2
  for s in kant-relay kant-zk-forward kant-zk-archive kant-zk-publisher; do
    systemctl is-active --quiet "$s" && info "  $s: active" || warn "  $s: NOT ACTIVE"
  done
}

cf_worker() {
  info "deploying CF worker ($WORKER_NAME)…"
  (cd server && PATH="$PROFILE_BIN:$PATH" CLOUDFLARE_API_TOKEN="$(cat "$CF_TOKEN_FILE")" \
    npx wrangler deploy)
}

cf_pages() {
  info "deploying CF Pages (kant-zk-pastebin)…"
  "$NODE" server/publisher.mjs --once --pages-deploy \
    --spool /var/spool/uucp/pastebin --out /var/lib/kant-zk/snapshot
}

health() {
  info "local relay:  $(curl -sf "$RELAY_LOCAL_URL/room/0000000000000000000000000000000000000000000000000000000000000000" -o /dev/null -w '%{http_code}' || echo DOWN)"
  info "cf worker:    $(curl -sf "$WORKER_URL/room/0000000000000000000000000000000000000000000000000000000000000000" -o /dev/null -w '%{http_code}' || echo DOWN)"
  info "cf pages:     $(curl -sf "$PAGES_URL/paste" -o /dev/null -w '%{http_code}' || echo DOWN)"
  info "archive idx:  $(curl -sf "$PAGES_URL/archive/" -o /dev/null -w '%{http_code}' || echo DOWN)"
}

case "${1:-all}" in
  check)  preflight ;;
  local)  preflight; local_services ;;
  cf)     preflight; cf_worker; cf_pages ;;
  status) health ;;
  all)    preflight; local_services; cf_worker; cf_pages; health ;;
  *) echo "usage: $0 {all|local|cf|status|check}" >&2; exit 2 ;;
esac
