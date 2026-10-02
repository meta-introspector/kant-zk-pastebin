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

# Check if GPG keys are available
echo "Checking GPG keys..."
if ! gpg --list-keys A76A0CF9079EC60D 445EB57704130B8D &>/dev/null; then
    echo "WARNING: GPG keys not found in local keyring."
    echo "You may need to import the keys first:"
    echo "  gpg --import <path-to-public-keys>"
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

# Create the credentials YAML
cat > /tmp/cloudflare-creds.yaml <<CREDS_EOF
cloudflare:
  api_token: "$CF_API_TOKEN"
  account_id: "$CF_ACCOUNT_ID"
CREDS_EOF

# Encrypt with sops
echo "Encrypting credentials..."
sops --encrypt \
  --pgp A76A0CF9079EC60D \
  --pgp 445EB57704130B8D \
  --input-type yaml \
  --output-type yaml \
  /tmp/cloudflare-creds.yaml > .sops/credentials.sops.yaml

# Clean up
rm /tmp/cloudflare-creds.yaml

echo ""
echo "✅ Credentials encrypted to .sops/credentials.sops.yaml"
echo ""
echo "You can now deploy the Cloudflare worker:"
echo "  ./deploy-cloudflare-worker.sh deploy"
