#!/usr/bin/env bash
echo "=== kant-pastebin-lean-dev ==="
systemctl status kant-pastebin-lean-dev --no-pager -l
echo "PID: 4069993  Memory: 60612 KB  CPU: 0.0017732251862994822%"
journalctl -u kant-pastebin-lean-dev --since "10 min ago" --no-pager | tail -10
