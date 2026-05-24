#!/usr/bin/env bash
set -e

echo "=== Deploying Kant Pastebin ==="
nix build 2>&1 || { echo "⚠️  nix build failed, trying cargo build..."; cargo build; }

STORE_PATH=$(readlink -f result 2>/dev/null || echo "./target/debug")
BINARY="$STORE_PATH/bin/kant-pastebin"
[ -x "$BINARY" ] || BINARY="./target/debug/kant-pastebin"
[ -x "$BINARY" ] || { echo "Binary not found at $BINARY"; exit 1; }

echo "Built: $BINARY"
echo ""
echo "To run manually:"
echo "  export DAGCBOR_TILES_PATH=/mnt/data1/time-2026/02-february/22/dasl/dasl-testing/sheaf/tiles/dagcbor_tiles.html"
echo "  RUST_LOG=info $BINARY"
echo ""
echo "Or install systemd service:"
cat > kant-pastebin.service << UNIT
[Unit]
Description=Kant Pastebin
After=network.target
[Service]
Type=simple
WorkingDirectory=$(pwd)
ExecStart=$BINARY
Restart=always
RestartSec=10
Environment=BIND_ADDR=127.0.0.1:8090
Environment=UUCP_SPOOL=/mnt/data1/spool/uucp/pastebin
Environment=DAGCBOR_TILES_PATH=/mnt/data1/time-2026/02-february/22/dasl/dasl-testing/sheaf/tiles/dagcbor_tiles.html
Environment=RUST_LOG=info
[Install]
WantedBy=default.target
UNIT
echo "  Systemd: cp kant-pastebin.service ~/.config/systemd/user/ && systemctl --user daemon-reload && systemctl --user restart kant-pastebin"
echo ""
echo "Test: curl -s http://127.0.0.1:8090/ | head -5"
