#!/usr/bin/env bash
echo "=== kant-pastebin-relay ==="
systemctl status kant-pastebin-relay --no-pager -l
echo "PID: 1571584  Memory: 43472 KB  CPU: 0.001242283112498927%"
journalctl -u kant-pastebin-relay --since "10 min ago" --no-pager | tail -10
