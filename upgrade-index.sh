#!/usr/bin/env bash
# Upgrade index entries with missing fields

UUCP_DIR="/mnt/data1/spool/uucp/pastebin"
INDEX="$UUCP_DIR/index.jsonl"
TEMP_INDEX="$UUCP_DIR/index.jsonl.tmp"

echo "=== Upgrading index entries ==="

> "$TEMP_INDEX"

jq -c '.' "$INDEX" | while IFS= read -r line; do
    # Add missing fields with defaults
    echo "$line" | jq -c '
        .ngrams = (.ngrams // []) |
        .reply_to = (.reply_to // null) |
        .size = (.size // 0) |
        .uucp_path = (.uucp_path // ("/mnt/data1/spool/uucp/pastebin/" + .filename))
    ' >> "$TEMP_INDEX"
done

mv "$TEMP_INDEX" "$INDEX"
echo "✅ Done! Upgraded $(wc -l < "$INDEX") entries"
