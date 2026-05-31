#!/usr/bin/env bash
set -e

echo "=== Deploying Kant Pastebin ==="
echo ""
echo "Choose deployment method:"
echo "  1) Pipelight (background orchestration)  — pipelight run deploy"
echo "  2) Direct (system-manager)               — this script"
echo "  3) Full build + deploy (pipelight)       — pipelight run full-deploy"
echo ""
read -rp "Method [1-3] (default: 2): " method
method="${method:-2}"

case "$method" in
  1)
    echo "=== Deploying via Pipelight ==="
    cd /home/mdupont/pastebin
    nix run .#pipelight -- run deploy
    ;;
  3)
    echo "=== Full build + deploy via Pipelight ==="
    cd /home/mdupont/pastebin
    nix run .#pipelight -- run full-deploy
    ;;
  2|*)
    echo "=== Direct deployment via System Manager ==="
    echo ""

    echo ""

    # Pure build: all crate deps vendored locally (no crates.io).
    # Both system-manager (commit 3dd7dbe) and pipelight (commit f2de5e5)
    # use cargoVendorDir = "vendor" with all crate sources committed to
    # their local git mirrors. PIPELIGHT_CMD is resolved dynamically
    # from the flake package, not a hardcoded store path.
    echo "--- Building system config (pure, no network) ---"
    STORE_PATH=$(nix build ".#systemConfigs.kant-pastebin" --no-link --print-out-paths 2>&1)
    echo "Built: $STORE_PATH"
    UNIT_FILE="$STORE_PATH/services/kant-pastebin.service"

    if [ ! -f "$UNIT_FILE" ]; then
      echo "ERROR: Unit file not found at $UNIT_FILE"
      exit 1
    fi

    echo "Using unit: $UNIT_FILE"

    # ── Apply the unit file (requires sudo) ──────────────────────────
    echo ""
    echo "--- Copying unit file to /etc/systemd/system/ (requires sudo) ---"
    sudo cp "$UNIT_FILE" /etc/systemd/system/kant-pastebin.service
    sudo systemctl daemon-reload
    sudo systemctl restart kant-pastebin

    # ── Verification ─────────────────────────────────────────────────
    echo ""
    echo "--- Verification ---"

    echo "1. Service status:"
    systemctl status kant-pastebin --no-pager 2>&1 | head -8

    echo ""
    echo "2. PIPELIGHT_CMD in service environment:"
    if systemctl show kant-pastebin -p Environment 2>&1 | grep -q PIPELIGHT_CMD; then
      echo "   ✓ PIPELIGHT_CMD is set"
      systemctl show kant-pastebin -p Environment 2>&1 \
        | tr ' ' '\n' | grep PIPELIGHT_CMD
    else
      echo "   ✗ PIPELIGHT_CMD is NOT set — pipelight tile will fail"
    fi

    echo ""
    echo "3. HTTP health check:"
    http_code=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8090/ 2>/dev/null || echo "failed")
    echo "   HTTP $http_code from http://127.0.0.1:8090/"

    echo ""
    echo "4. Public endpoint:"
    echo "   https://solana.solfunmeme.com/pastebin/"
    ;;
esac

echo ""
echo "=== Deploy complete ==="
echo ""
echo "Available pipelight pipelines:"
echo "  nix run .#pipelight -- ls"
echo "  nix run .#pipelight -- run build-pastebin    # build only"
echo "  nix run .#pipelight -- run check-status       # check service"
echo "  nix run .#pipelight -- run reindex-docs       # re-index DOCS"
echo "  nix run .#pipelight -- run deploy             # build + deploy"
echo "  nix run .#pipelight -- run full-deploy        # all steps"
