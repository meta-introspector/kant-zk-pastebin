#!/usr/bin/env bash
# Add all existing pastes to IPFS and update index

UUCP_DIR="/mnt/data1/spool/uucp/pastebin"
INDEX="$UUCP_DIR/index.jsonl"
TEMP_INDEX="$UUCP_DIR/index.jsonl.tmp"

echo "=== Adding pastes to IPFS ==="

> "$TEMP_INDEX"

jq -c '.' "$INDEX" | while IFS= read -r line; do
    id=$(echo "$line" | jq -r '.id')
    ipfs_cid=$(echo "$line" | jq -r '.ipfs_cid')
    
    if [ "$ipfs_cid" = "null" ] || [ -z "$ipfs_cid" ]; then
        file="$UUCP_DIR/${id}.txt"
        if [ -f "$file" ]; then
            # Extract content (skip header)
            content=$(awk '/^$/{flag=1;next}flag' "$file")
            
            # Add to IPFS
            cid=$(echo "$content" | ipfs add -Q --pin=false 2>/dev/null)
            
            if [ -n "$cid" ]; then
                echo "✅ $id -> $cid"
                # Update JSON
                echo "$line" | jq -c --arg cid "$cid" '.ipfs_cid = $cid' >> "$TEMP_INDEX"
                
                # Update file header
                sed -i "s/^IPFS: $/IPFS: $cid/" "$file"
            else
                echo "❌ $id (ipfs failed)"
                echo "$line" >> "$TEMP_INDEX"
            fi
        else
            echo "⚠️  $id (file not found)"
            echo "$line" >> "$TEMP_INDEX"
        fi
    else
        echo "⏭️  $id (already has IPFS)"
        echo "$line" >> "$TEMP_INDEX"
    fi
done

mv "$TEMP_INDEX" "$INDEX"
echo ""
echo "✅ Done! Updated index.jsonl"
