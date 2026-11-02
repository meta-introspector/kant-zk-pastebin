#!/usr/bin/env bash
echo "=== kant-pastebin-beta ==="
systemctl status kant-pastebin-beta --no-pager -l
echo "PID: 3028489  Memory: 45480 KB  CPU: 0.14940842728239503%"
journalctl -u kant-pastebin-beta --since "10 min ago" --no-pager | tail -10
