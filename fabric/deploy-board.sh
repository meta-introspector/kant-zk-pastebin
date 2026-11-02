#!/usr/bin/env bash
# fabric/deploy-board.sh — deploy the agent-fabric Durable Object board.
#
# The board is the one piece Cloudflare owns that terraform must not: its
# class and its `new_sqlite_classes` migration live in wrangler.toml, and
# `cloudflare_worker_script` has no way to express either. So wrangler deploys
# the script; infra/src/main.rs only attaches the hostname to it.
#
# Credentials come from the same sops file the other Cloudflare scripts use
# (.sops/registry.sops.yaml → cloudflare.api_token / cloudflare.account_id),
# decrypted into a 0600 temp file and exported, never passed as an argument:
# an argument is visible in `ps` to every user on the box.
#
#   fabric/deploy-board.sh            deploy
#   fabric/deploy-board.sh --check    decrypt + verify credentials, deploy nothing
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
DURABLE="${SCRIPT_DIR}/durable"
REGISTRY="${REPO_DIR}/.sops/registry.sops.yaml"

check_only=0
[ "${1:-}" = "--check" ] && check_only=1

fail() { echo "deploy-board: $*" >&2; exit 1; }

command -v wrangler >/dev/null 2>&1 || fail "wrangler is not on PATH"
command -v sops >/dev/null 2>&1 || fail "sops is not on PATH"
[ -f "$REGISTRY" ] || fail "no credential registry at $REGISTRY (run scripts/setup-cloudflare-credentials.sh)"
[ -f "${DURABLE}/wrangler.toml" ] || fail "no wrangler.toml in ${DURABLE}"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

# -d --extract reads a single path out of the encrypted document; the plaintext
# never lands on disk.
token="$(sops --decrypt --extract '["cloudflare"]["api_token"]' "$REGISTRY" 2>/dev/null | tr -d '"[:space:]')"
account="$(sops --decrypt --extract '["cloudflare"]["account_id"]' "$REGISTRY" 2>/dev/null | tr -d '"[:space:]')"

[ -n "$token" ] || fail "registry holds no cloudflare.api_token"
[ -n "$account" ] || fail "registry holds no cloudflare.account_id"

if [ "$check_only" -eq 1 ]; then
  echo "deploy-board: credentials present (account ${account:0:6}…, token ${#token} chars); nothing deployed"
  exit 0
fi

export CLOUDFLARE_API_TOKEN="$token"
export CLOUDFLARE_ACCOUNT_ID="$account"
# Wrangler would otherwise ask about metrics on a first run in a clean HOME.
export WRANGLER_SEND_METRICS=false
export CI=1

cd "$DURABLE"
echo "deploy-board: deploying $(grep -E '^name' wrangler.toml | head -1) to account ${account:0:6}…"
exec wrangler deploy
