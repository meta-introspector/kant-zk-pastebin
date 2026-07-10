#!/usr/bin/env bash
# SVG→GIF worker — renders SVG SMIL animations faithfully using svg2anim-frames.
# Watches for job files in /var/spool/uucp/pastebin/svg2anim-jobs/
# Each job file contains the SVG paste ID.
# Output is saved back to the pastebin spool and indexed.
set -euo pipefail

SPOOL="${UUCP_SPOOL:-/var/spool/uucp/pastebin}"
JOBS_DIR="${SPOOL}/svg2anim-jobs"
SVG2ANIM_FRAMES="${SVG2ANIM_FRAMES_BIN:-/mnt/data1/time-2026/06-june/26/svg2anim-frames/target/debug/svg2anim-frames}"
FPS="${SVG2ANIM_FPS:-5}"

mkdir -p "$JOBS_DIR"

log() { echo "[svg2anim-worker] $(date -u +%Y-%m-%dT%H:%M:%SZ) $*"; }

process_svg() {
    local id="$1"
    local svg_file
    svg_file=$(find "$SPOOL" -maxdepth 1 -name "${id}.svg" -o -name "${id}.*.svg" 2>/dev/null | head -1)

    if [ -z "$svg_file" ]; then
        log "SVG not found for id=$id"
        return 1
    fi

    local ts
    ts=$(date -u +%Y%m%d_%H%M%S)
    local gif_fn="${ts}_${id}.gif"
    local gif_path="${SPOOL}/${gif_fn}"

    log "Processing: $svg_file -> $gif_fn"

    if ! "$SVG2ANIM_FRAMES" "$svg_file" --output "$gif_path" --fps "$FPS" 2>&1; then
        log "svg2anim-frames failed for $id"
        return 1
    fi

    local gif_size
    gif_size=$(stat -c%s "$gif_path" 2>/dev/null || stat -f%z "$gif_path" 2>/dev/null)

    # Compute SHA256 for CID
    local cid wit
    cid=$(sha256sum "$gif_path" | cut -c1-32)
    wit=$(sha256sum "$gif_path" | cut -c1-64)

    # Write index entry
    local gif_id="${ts}_${id}"
    local entry
    entry=$(cat <<ENDJSON
{"id":"$gif_id","title":"$id (animated)","description":"Animated GIF from SVG SMIL animations","keywords":["svg","animation","gif"],"cid":"bafk$cid","witness":"$wit","timestamp":"$ts","filename":"$gif_fn","size":$gif_size,"mime":"image/gif","ipfs_cid":null,"reply_to":null,"root":null,"uucp_path":"${gif_path}"}
ENDJSON
)
    echo "$entry" >> "${SPOOL}/index.jsonl"

    log "Created: $gif_id (${gif_size}B)"
}

# Main loop — process job files
log "Worker started, watching $JOBS_DIR"
while true; do
    for job in "$JOBS_DIR"/*; do
        [ -f "$job" ] || continue
        id=$(basename "$job")
        log "Job: $id"
        if process_svg "$id"; then
            rm -f "$job"
            log "Completed: $id"
        else
            mv "$job" "${job}.failed"
            log "Failed: $id"
        fi
    done
    sleep 5
done
