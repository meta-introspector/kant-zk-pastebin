#!/bin/bash
# kant-zk-archive-cron — single poll cycle for cron
#
# Install:
#   chmod +x kant-zk-archive-cron
#   # Add to crontab:
#   */5 * * * * /home/mdupont/projects/pastebin-lean/deploy/cron/kant-zk-archive-cron
#
# Logs to /var/log/kant-zk-archive-cron.log

set -euo pipefail

cd /home/mdupont/projects/pastebin-lean
exec /usr/bin/node server/archive.mjs \
  --rooms /var/lib/kant-zk/rooms \
  --relay https://solana.solfunmeme.com/relay \
  --backend https://solana.solfunmeme.com/pastebin \
  --once \
  >> /var/log/kant-zk-archive-cron.log 2>&1
