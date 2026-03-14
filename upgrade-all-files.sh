#!/usr/bin/env bash
# Add IPFS CIDs to all paste files

SPOOL="/mnt/data1/spool/uucp/pastebin"
IPFS="/nix/store/6avpxclcjrgm0ll1a9dp8638haw0jyn8-kubo-0.39.0/bin/ipfs"

echo "🔄 Upgrading all paste files..."

count=0
for file in "$SPOOL"/*.txt; do
  [ -f "$file" ] || continue
  
  # Check if IPFS field exists and is not empty
  ipfs_line=$(grep "^IPFS:" "$file" 2>/dev/null)
  ipfs_val=$(echo "$ipfs_line" | cut -d: -f2- | xargs)
  
  if [ -z "$ipfs_val" ]; then
    # Extract content (skip header)
    content=$(sed -n '/^$/,$p' "$file" | tail -n +2)
    
    # Generate IPFS CID
    cid=$(echo "$content" | "$IPFS" add -Q --pin=false 2>/dev/null)
    
    if [ -n "$cid" ]; then
      basename=$(basename "$file")
      echo "  $basename -> $cid"
      
      # Update file: add IPFS field if missing, or update empty one
      if grep -q "^IPFS:" "$file"; then
        sed -i "s|^IPFS:.*|IPFS: $cid|" "$file"
      else
        # Insert IPFS line after Witness line
        sed -i "/^Witness:/a IPFS: $cid" "$file"
      fi
      
      count=$((count + 1))
    fi
  fi
done

echo ""
echo "✅ Added IPFS CIDs to $count pastes"
