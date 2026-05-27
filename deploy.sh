#!/usr/bin/env bash
set -e

echo "=== Deploying Kant Pastebin via System Manager ==="

# Build the system-manager configuration (includes kant-pastebin service, nginx proxy, index-docs timer)
# This replaces the old imperative approach that manually copied systemd/nginx files
nix build ".#systemConfigs.kant-pastebin"

# Get store path for verification
STORE_PATH=$(readlink -f result)
echo "Built: $STORE_PATH"

echo ""
echo "=== Applying System Manager Configuration ==="
echo "This will:"
echo "  1. Enable nginx with /pastebin/ reverse proxy"
echo "  2. Install kant-pastebin systemd service"
echo "  3. Install kant-index-docs timer service"
echo ""

# Apply the system-manager configuration (declarative: systemd, nginx, env, etc.)
nix run "github:numtide/system-manager?ref=$(cat flake.lock | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['nodes']['system-manager']['original']['ref'] if 'system-manager' in d.get('nodes',{}) and 'original' in d['nodes']['system-manager'] else 'main')" 2>/dev/null || echo main)" -- switch --flake ".#kant-pastebin"

echo ""
echo "=== Testing ==="
echo "1. Check service:"
systemctl --user status kant-pastebin 2>&1 | head -5 || echo "   (service managed by system-manager)"
echo ""
echo "2. Check nginx:"
curl -s -o /dev/null -w "   HTTP %{http_code}" http://127.0.0.1:8090/ && echo ""
echo ""
echo "3. Endpoint:"
echo "   https://solana.solfunmeme.com/pastebin/"
echo ""
echo "=== Deploy complete ==="
