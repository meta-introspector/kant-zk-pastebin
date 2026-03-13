#!/usr/bin/env bash
# One-time upgrade of all pastes with auto-tags and descriptions

echo "🔄 Upgrading all pastes with auto-tags..."

curl -s -X POST http://127.0.0.1:8090/upgrade | jq '.'

echo ""
echo "✅ Upgrade complete!"
