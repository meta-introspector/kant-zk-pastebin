#!/usr/bin/env bash
echo "=== kant-pastebin-lean-relay ==="
systemctl status kant-pastebin-lean-relay --no-pager -l
echo "PID: 1571583  Memory: 43400 KB  CPU: 0.0012104308560485536%"
journalctl -u kant-pastebin-lean-relay --since "10 min ago" --no-pager | tail -10
