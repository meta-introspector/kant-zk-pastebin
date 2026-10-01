#!/usr/bin/env bash
set -euo pipefail

PASTEBIN_DIR="${PASTEBIN_DIR:-/home/mdupont/pastebin}"
LOG_DIR="${PASTEBIN_DIR}/logs"
LOG_FILE="${LOG_DIR}/deploy-background.log"
PID_FILE="${LOG_DIR}/deploy-background.pid"

cd "$PASTEBIN_DIR"
mkdir -p "$LOG_DIR"

if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "Background deploy already running with PID $(cat "$PID_FILE")"
  echo "Log: $LOG_FILE"
  exit 0
fi

nohup bash deploy.sh deploy >"$LOG_FILE" 2>&1 &
pid=$!
echo "$pid" >"$PID_FILE"
echo "Started background deploy PID=$pid"
echo "Log: $LOG_FILE"
echo "PID file: $PID_FILE"
