#!/usr/bin/env bash
set -e

echo "=== Deploying Kant Pastebin ==="

# Build with Nix
nix build

# Get Nix store path
STORE_PATH=$(readlink -f result)
echo "Built: $STORE_PATH"

# Generate systemd service
cat > kant-pastebin.service << EOF
[Unit]
Description=Kant Pastebin - UUCP + zkTLS
After=network.target

[Service]
Type=simple
WorkingDirectory=$(pwd)
ExecStart=$STORE_PATH/bin/kant-pastebin
Restart=always
RestartSec=10
Environment="BIND_ADDR=127.0.0.1:8090"
Environment="UUCP_SPOOL=/var/spool/uucp/pastebin"
Environment="RUST_LOG=info"

[Install]
WantedBy=default.target
EOF

# Generate nginx config
cat > kant-pastebin.nginx << 'EOF'
location ^~ /pastebin/ {
    proxy_pass http://127.0.0.1:8090/;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
}
EOF

echo ""
echo "=== Install ==="
echo "1. Systemd:"
echo "   cp kant-pastebin.service ~/.config/systemd/user/"
echo "   systemctl --user daemon-reload"
echo "   systemctl --user enable --now kant-pastebin"
echo ""
echo "2. Nginx (add to server block BEFORE location /):"
echo "   cat kant-pastebin.nginx"
echo ""
echo "3. Test:"
echo "   curl http://127.0.0.1:8090/"
echo "   https://solana.solfunmeme.com/pastebin/"
