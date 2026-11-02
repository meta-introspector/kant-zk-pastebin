#!/usr/bin/env bash
# Setup Cloudflare credentials with SOPS

set -euo pipefail

echo "=== Cloudflare Credentials Setup ==="
echo ""
echo "This script will encrypt your Cloudflare API token and account ID using SOPS."
echo "You need:"
echo "  1. A Cloudflare API Token with Workers and KV permissions"
echo "  2. Your Cloudflare Account ID"
echo ""

# Check if sops is available
if ! command -v sops &>/dev/null; then
    echo "ERROR: sops not found. Please install sops first."
    exit 1
fi

export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
if [ ! -f "$SOPS_AGE_KEY_FILE" ]; then
    echo "ERROR: no age key at $SOPS_AGE_KEY_FILE — sops cannot re-encrypt the registry"
    echo "       without the private half. Set SOPS_AGE_KEY_FILE if it lives elsewhere."
    exit 1
fi

# Prompt for credentials
read -p "Enter Cloudflare API Token: " -s CF_API_TOKEN
echo ""
read -p "Enter Cloudflare Account ID: " CF_ACCOUNT_ID
echo ""

if [ -z "$CF_API_TOKEN" ] || [ -z "$CF_ACCOUNT_ID" ]; then
    echo "ERROR: Both API Token and Account ID are required"
    exit 1
fi

# One registry for the repo: .sops/registry.sops.yaml. scripts/sops-run.sh,
# deploy-cloudflare-worker.sh and scripts/deploy-all.sh all read it, and
# scripts/sops-set.sh writes it. Merge into it rather than writing a fresh
# file over the top: the registry's other keys are in active use.
#
# `sops set` is not in sops 3.8.1 (it falls through to `sops edit` and opens
# $EDITOR), so this follows sops-set.sh's shape instead: decrypt to a 0600
# temp file, edit it with python, re-encrypt over the original. Single quotes
# in the heredoc keep the shell out of the values.
REGISTRY=".sops/registry.sops.yaml"
echo "Encrypting credentials into $REGISTRY..."
mkdir -p .sops
[ -f "$REGISTRY" ] || printf 'cloudflare: {}\n' | sops --encrypt \
    --input-type yaml --output-type yaml /dev/stdin > "$REGISTRY"
chmod 600 "$REGISTRY"

WORK="$(mktemp)"; trap 'rm -f "$WORK"' EXIT
chmod 600 "$WORK"
sops -d --output-type json "$REGISTRY" > "$WORK" 2>/dev/null || {
    echo "ERROR: cannot decrypt $REGISTRY with $SOPS_AGE_KEY_FILE"
    exit 1
}
python3 - "$WORK" "$CF_API_TOKEN" "$CF_ACCOUNT_ID" <<'PY'
import json, sys
path, token, account = sys.argv[1], sys.argv[2], sys.argv[3]
doc = json.load(open(path))
cf = doc.get("cloudflare")
if not isinstance(cf, dict):
    cf = {}
cf["api_token"] = token
cf["account_id"] = account
doc["cloudflare"] = cf
json.dump(doc, open(path, "w"), indent=2, sort_keys=True)
PY
AGE_PUB="$(grep -o 'age1[a-z0-9]*' .sops.yaml | head -1)"
PGP_FPR="$(grep -oE 'pgp: *"[^"]+"' .sops.yaml | head -1 | sed 's/.*"\(.*\)"/\1/')"
sops --encrypt --age "$AGE_PUB" --pgp "$PGP_FPR" \
    --input-type json --output-type yaml "$WORK" > "$REGISTRY.tmp" || {
    rm -f "$REGISTRY.tmp"
    echo "ERROR: re-encrypt failed; $REGISTRY left untouched"
    exit 1
}
mv "$REGISTRY.tmp" "$REGISTRY"
chmod 600 "$REGISTRY"
rm -f "$WORK"; trap - EXIT
unset CF_API_TOKEN CF_ACCOUNT_ID

echo ""
echo "✅ Credentials encrypted into $REGISTRY"
echo ""
echo "You can now deploy the Cloudflare worker:"
echo "  ./deploy-cloudflare-worker.sh deploy"
