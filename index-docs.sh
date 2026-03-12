#!/bin/bash
set -e

PASTEBIN_URL="http://127.0.0.1:8090/paste"
DOCS_DIR="$HOME/DOCS"
SPOOL_DIR="$HOME/spool"

index_file() {
    local file="$1"
    local title=$(basename "$file")
    local size=$(stat -c%s "$file" 2>/dev/null || echo 0)
    
    if [ "$size" -gt 1048576 ]; then return; fi
    
    local content=$(cat "$file" 2>/dev/null || echo "")
    if [ -z "$content" ] || [ ${#content} -lt 10 ]; then return; fi
    
    local keywords=$(echo "$title" | tr '._-' '\n' | grep -E '^[a-zA-Z0-9]+$' | sort -u | head -10 | jq -R . | jq -s .)
    
    echo "Indexing: $title"
    
    local payload=$(jq -n \
        --arg t "$title" \
        --arg c "$content" \
        --argjson k "$keywords" \
        '{title:$t,content:$c,keywords:$k}')
    
    curl -s -X POST "$PASTEBIN_URL" \
        -H "Content-Type: application/json" \
        -d "$payload" | jq -r '.id // empty'
}

echo "🔍 Indexing ~/DOCS..."
find "$DOCS_DIR" -type f \( -name "*.md" -o -name "*.txt" -o -name "*.org" \) 2>/dev/null | while read f; do
    index_file "$f"
done

echo "🔍 Indexing ~/spool..."
find "$SPOOL_DIR" -maxdepth 2 -type f \( -name "*.md" -o -name "*.txt" \) 2>/dev/null | head -30 | while read f; do
    index_file "$f"
done

echo "✅ Indexing complete!"
