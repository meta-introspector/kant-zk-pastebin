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
Environment="UUCP_SPOOL=/mnt/data1/spool/uucp/pastebin"
Environment="BASE_PATH=/pastebin"
Environment="RUST_LOG=info"

[Install]
WantedBy=default.target
EOF

# Generate nginx config
cat > kant-pastebin.nginx << 'EOF'
location /pastebin/ {
    proxy_pass http://127.0.0.1:8090/;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
EOF

echo ""
echo "=== Install ==="
echo "1. Systemd:"
cp kant-pastebin.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user restart kant-pastebin
echo "   ✅ Service restarted"
echo ""
echo "2. Nginx:"
sudo cp kant-pastebin.nginx /etc/nginx/conf.d/kant-pastebin.conf
sudo nginx -t && sudo systemctl reload nginx
echo "   ✅ Nginx reloaded"
echo ""
echo "3. Test:"
curl -s http://127.0.0.1:8090/ | head -5
echo ""
echo "   https://solana.solfunmeme.com/pastebin/"
