#!/usr/bin/env bash
# Add all paste files to index

SPOOL="/mnt/data1/spool/uucp/pastebin"
INDEX="$SPOOL/index.jsonl"

echo "🔍 Finding all paste files..."

# Get existing IDs
existing_ids=$(cat "$INDEX" 2>/dev/null | jq -r '.id' | sort)

# Find all .txt files
for file in "$SPOOL"/*.txt; do
  [ -f "$file" ] || continue
  
  filename=$(basename "$file")
  id="${filename%.txt}"
  
  # Check if already in index
  if echo "$existing_ids" | grep -q "^$id$"; then
    continue
  fi
  
  echo "Adding: $id"
  
  # Extract header info
  title=$(grep "^Title:" "$file" | cut -d: -f2- | xargs)
  keywords=$(grep "^Keywords:" "$file" | cut -d: -f2- | xargs)
  cid=$(grep "^CID:" "$file" | cut -d: -f2- | xargs)
  witness=$(grep "^Witness:" "$file" | cut -d: -f2- | xargs)
  ipfs_cid=$(grep "^IPFS:" "$file" | cut -d: -f2- | xargs)
  
  # Get timestamp from filename
  timestamp=$(echo "$id" | cut -d_ -f1-2 | sed 's/_//')
  
  # Get file size
  size=$(wc -c < "$file")
  
  # Create JSON entry
  jq -n \
    --arg id "$id" \
    --arg title "$title" \
    --arg keywords "$keywords" \
    --arg cid "$cid" \
    --arg witness "$witness" \
    --arg timestamp "$timestamp" \
    --arg filename "$filename" \
    --arg ipfs_cid "$ipfs_cid" \
    --arg size "$size" \
    --arg uucp_path "$file" \
    '{
      id: $id,
      title: $title,
      description: null,
      keywords: ($keywords | split(",") | map(select(length > 0))),
      cid: $cid,
      witness: $witness,
      timestamp: $timestamp,
      filename: $filename,
      ngrams: [],
      ipfs_cid: (if $ipfs_cid == "" then null else $ipfs_cid end),
      reply_to: null,
      size: ($size | tonumber),
      uucp_path: $uucp_path
    }' >> "$INDEX"
done

echo "✅ Reindexing complete!"
echo "Now run: cd /mnt/data1/kant/pastebin/upgrade-cli && ./target/release/upgrade-cli"
