#!/usr/bin/env bash
# join-and-post.sh — join Kant rooms from invites.txt and post "hello world"
#
# Usage:
#   ./scripts/join-and-post.sh [invites-file]
#
# Default invites file: scripts/invites.txt
# Each line should be a Kant invite URL.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INVITES_FILE="${1:-$SCRIPT_DIR/invites.txt}"
STATE_DIR="${STATE_DIR:-/tmp/kant-join-post}"
CLI="$SCRIPT_DIR/kant-cli.mjs"

mkdir -p "$STATE_DIR"

echo "=== Kant Join and Post ==="
echo "Invites file: $INVITES_FILE"
echo "State dir: $STATE_DIR"
echo ""

LINE_NUM=0
while IFS= read -r INVITE_URL; do
  LINE_NUM=$((LINE_NUM + 1))
  
  # Skip empty lines and comments
  [[ -z "$INVITE_URL" || "$INVITE_URL" =~ ^# ]] && continue
  
  echo "--- Invite $LINE_NUM ---"
  echo "URL: $INVITE_URL"
  
  STATE_FILE="$STATE_DIR/invite-$LINE_NUM.json"
  
  # Join the room
  echo "Joining room..."
  JOIN_RESULT=$(node "$CLI" --state "$STATE_FILE" join "$INVITE_URL" --json 2>&1)
  echo "$JOIN_RESULT"
  
  # Post "hello world"
  echo ""
  echo "Posting 'hello world'..."
  POST_RESULT=$(node "$CLI" --state "$STATE_FILE" say "hello world" --transport curl --json 2>&1)
  
  if echo "$POST_RESULT" | grep -q '"ok":[[:space:]]*true'; then
    echo "✅ Successfully posted 'hello world'"
  else
    echo "⚠️  Post failed: $POST_RESULT"
  fi
  
  echo ""
done < "$INVITES_FILE"

echo "=== Join and Post Complete ==="
echo ""
echo "State files:"
ls -la "$STATE_DIR/" 2>/dev/null || echo "(none)"
echo ""
echo "To read the rooms later:"
for f in "$STATE_DIR"/invite-*.json; do
  [ -f "$f" ] && echo "  node $CLI --state $f read --transport curl"
done