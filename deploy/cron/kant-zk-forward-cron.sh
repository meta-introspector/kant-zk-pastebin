#!/bin/bash
# kant-zk-forward-cron — single poll cycle for cron
#
# Install:
#   chmod +x kant-zk-forward-cron
#   # Add to crontab:
#   */2 * * * * /home/mdupont/projects/pastebin-lean/deploy/cron/kant-zk-forward-cron
#
# Logs to /var/log/kant-zk-forward-cron.log

set -euo pipefail

: "${KANT_ZK_INVITE:=https://solana.solfunmeme.com/relay/#6b7a696e76697465:68747470733a2f2f736f6c616e612e736f6c66756e6d656d652e636f6d2f72656c6179:f436f2a7fc1378621989a2121aed902a53fe120ee4be013e1d412ed9a279c792:6c65747461}"

cd /home/mdupont/projects/pastebin-lean
exec /usr/bin/node server/forward.mjs \
  --invite "$KANT_ZK_INVITE" \
  --from https://solana.solfunmeme.com/relay \
  --to https://kant-zk-relay.jmikedupont2.workers.dev \
  --state /var/lib/kant-zk/forward-state.json \
  --once \
  >> /var/log/kant-zk-forward-cron.log 2>&1
