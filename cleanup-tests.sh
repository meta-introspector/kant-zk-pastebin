#!/usr/bin/env bash
# Remove small test pastes

SPOOL="/mnt/data1/spool/uucp/pastebin"

echo "🗑️  Finding small test pastes to delete..."

# Find test pastes under 500 bytes
find "$SPOOL" -type f -name "*.txt" -size -500c | while read file; do
  basename=$(basename "$file")
  
  # Skip if it looks important (not test/untitled)
  if [[ ! "$basename" =~ (test|untitled|paste_) ]]; then
    continue
  fi
  
  echo "  $basename ($(stat -f%z "$file" 2>/dev/null || stat -c%s "$file") bytes)"
done

echo ""
read -p "Delete these files? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  find "$SPOOL" -type f -name "*.txt" -size -500c | while read file; do
    basename=$(basename "$file")
    if [[ "$basename" =~ (test|untitled|paste_) ]]; then
      rm "$file"
      echo "  Deleted: $basename"
    fi
  done
  echo "✅ Cleanup complete!"
else
  echo "Cancelled."
fi
