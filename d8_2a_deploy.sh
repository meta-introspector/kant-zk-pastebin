#!/bin/bash
# D8 2A eBPF Monitoring - Deploy Script
# https://github.com/Kilo-Org/kilocode

set -e

AYA_DIR="/mnt/data1/nix/vendor/rust/cargo2nix/submodules/cargo-clean/tools/cargo-vendormod/aya-nix"
SERVICE_FILE="/home/mdupont/pastebin/d8_2a.service"

echo "=== D8 2A eBPF Monitor Deploy ==="
echo ""

# Build
echo "Building d8_2a eBPF monitor..."
cd "$AYA_DIR"
nix develop -c cargo build --target bpfel-unknown-none --release -p d8_2a_monitor
nix develop -c cargo build --release -p d8_2a_loader

# Install systemd service
echo ""
echo "Installing systemd service..."
sudo cp "$SERVICE_FILE" /etc/systemd/system/d8_2a-monitor.service
sudo systemctl daemon-reload

# Start
echo ""
echo "Starting d8_2a-monitor service..."
sudo systemctl restart d8_2a-monitor
sudo systemctl status d8_2a-monitor --no-pager

echo ""
echo "Hits will be written to /tmp/d8_2a_hits.dagcbor"
echo ""
echo "To run tests with monitoring:"
echo "  make -C $AYA_DIR test"