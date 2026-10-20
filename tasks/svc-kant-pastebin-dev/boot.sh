#!/usr/bin/env bash
echo "=== kant-pastebin-dev ==="
systemctl status kant-pastebin-dev --no-pager -l
echo "PID: 4169371  Memory: 72348 KB  CPU: 0.003614071949941364%"
journalctl -u kant-pastebin-dev --since "10 min ago" --no-pager | tail -10
