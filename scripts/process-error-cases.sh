#!/usr/bin/env bash
# Process nginx error-docs/error.log into individual markdown case files
set -euo pipefail

ERROR_LOG="/var/log/nginx/error-docs/error.log"
CASES_DIR="/var/log/nginx/error-docs/cases"
SEEN_FILE="/var/log/nginx/error-docs/.processed_lines"

mkdir -p "$CASES_DIR"
touch "$SEEN_FILE"

# Get the number of lines already processed
seen_lines=$(wc -l < "$SEEN_FILE" 2>/dev/null || echo 0)
total_lines=$(wc -l < "$ERROR_LOG" 2>/dev/null || echo 0)

if [ "$total_lines" -le "$seen_lines" ]; then
    exit 0  # Nothing new
fi

# Read new entries from the error log
# Each entry starts with "=== Error Document ===" and ends with "-------------------"
awk -v seen="$seen_lines" -v cases="$CASES_DIR" '
BEGIN { entry = ""; line_num = 0; in_entry = 0; case_count = 0; ts = ""; uri = ""; status = ""; client = "" }

{
    line_num++
    if (line_num <= seen) next
    
    if ($0 ~ /^[[:space:]]*=== Error Document ===/) {
        in_entry = 1
        entry = $0 "\n"
        next
    }
    
    if (in_entry) {
        entry = entry $0 "\n"
        
        if ($0 ~ /Date:/) { ts = $2 }
        if ($0 ~ /Client:/) { client = $2 }
        if ($0 ~ /URI:/) { uri = $2 }
        if ($0 ~ /Status:/) { status = $2 }
        
        if ($0 ~ /^[[:space:]]*-------------------/) {
            in_entry = 0
            case_count++
            
            # Create a sanitized filename
            gsub(/[\/: ]/, "_", ts)
            gsub(/[?&\/]/, "_", uri)
            slug = status
            if (uri != "") {
                n = split(uri, parts, "/")
                slug = parts[n]
                gsub(/[^a-zA-Z0-9_.-]/, "_", slug)
                if (length(slug) > 40) slug = substr(slug, 1, 40)
            }
            
            filename = sprintf("%s/case_%s_%s_%s.md", cases, ts, status, slug)
            printf "%s", entry > filename
            close(filename)
            
            # Reset
            ts = ""; uri = ""; status = ""; client = ""
            entry = ""
        }
    }
}

END {
    # Update seen counter
    print line_num > "'"$SEEN_FILE"'"
    if (case_count > 0) {
        print "Processed " case_count " error cases into " cases
    }
}
' "$ERROR_LOG"
