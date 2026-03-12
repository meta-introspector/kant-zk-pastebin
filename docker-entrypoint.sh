#!/bin/bash
set -e

# Start IPFS daemon in background
echo "Starting IPFS daemon..."
ipfs daemon --offline &
IPFS_PID=$!

# Wait for IPFS to be ready
sleep 3

# Start pastebin
echo "Starting Kant Pastebin..."
exec kant-pastebin
