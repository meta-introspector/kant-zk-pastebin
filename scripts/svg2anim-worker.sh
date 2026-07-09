#!/usr/bin/env bash
# SVG→animated GIF worker — standalone systemd service.
# Watches for job files in /var/spool/uucp/pastebin/svg2anim-jobs/
# Each job file contains the SVG paste ID.
# Output is saved back to the pastebin spool and indexed.
set -euo pipefail

RESVG="${RESVG_BIN:-/home/mdupont/2026/06/26/resvg/target/debug/resvg}"
SPOOL="${UUCP_SPOOL:-/var/spool/uucp/pastebin}"
JOBS_DIR="${SPOOL}/svg2anim-jobs"
NUM_FRAMES=24
MAX_DIM=800
DELAY_CS=4

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
    local tmp="/tmp/svg2anim_${ts}_${id}"
    mkdir -p "$tmp"

    log "Processing: $svg_file"

    # 1. Render base PNG via resvg
    if ! "$RESVG" "$svg_file" "$tmp/base.png" 2>/dev/null; then
        log "resvg failed for $id"
        rm -rf "$tmp"
        return 1
    fi

    # 2. Get dimensions
    local dims
    dims=$(identify -format "%w %h" "$tmp/base.png" 2>/dev/null || echo "400 400")
    local w h
    w=$(echo "$dims" | cut -d' ' -f1)
    h=$(echo "$dims" | cut -d' ' -f2)

    # Cap at MAX_DIM
    if [ "$w" -gt "$MAX_DIM" ] || [ "$h" -gt "$MAX_DIM" ]; then
        local s
        s=$(awk "BEGIN { printf \"%.4f\", $MAX_DIM / (($w > $h) ? $w : $h) }")
        w=$(awk "BEGIN { printf \"%.0f\", $w * $s }")
        h=$(awk "BEGIN { printf \"%.0f\", $h * $s }")
    fi
    [ "$w" -lt 100 ] && w=100
    [ "$h" -lt 100 ] && h=100

    # 3. Resize
    convert "$tmp/base.png" -resize "${w}x${h}!" "$tmp/src.png"

    # 4. Generate rotated frames
    for i in $(seq 0 $((NUM_FRAMES - 1))); do
        local angle
        angle=$(awk "BEGIN { printf \"%.2f\", $i * 360 / $NUM_FRAMES }")
        local fp
        fp=$(printf "$tmp/frame_%02d.png" "$i")
        if ! convert "$tmp/src.png" -background none -virtual-pixel transparent \
            -distort SRT "$angle" -gravity center -extent "${w}x${h}" "$fp" 2>/dev/null; then
            cp "$tmp/src.png" "$fp"
        fi
    done

    # 5. Combine into animated GIF
    local gif_out="${tmp}/out.gif"
    convert -delay "$DELAY_CS" -loop 0 "$tmp"/frame_*.png "$gif_out"

    # 6. Copy to spool
    local safe_id
    safe_id=$(echo "$id" | tr '.' '_')
    local gif_fn="${ts}_${safe_id}.gif"
    cp "$gif_out" "${SPOOL}/${gif_fn}"
    local gif_size
    gif_size=$(stat -c%s "$gif_out" 2>/dev/null || stat -f%z "$gif_out" 2>/dev/null)

    # 7. Compute SHA256 for CID
    local cid wit
    cid=$(sha256sum "$gif_out" | cut -c1-32)
    wit=$(sha256sum "$gif_out" | cut -c1-64)

    # 8. Write index entry
    local gif_id="${ts}_${safe_id}"
    local entry
    entry=$(cat <<ENDJSON
{"id":"$gif_id","title":"$id (animated)","description":"Animated GIF from SVG ($NUM_FRAMES frames ${w}x${h})","keywords":["svg","animation","gif"],"cid":"bafk$cid","witness":"$wit","timestamp":"$ts","filename":"$gif_fn","size":$gif_size,"mime":"image/gif","ipfs_cid":null,"reply_to":null,"root":null,"uucp_path":"${SPOOL}/${gif_fn}"}
ENDJSON
)
    echo "$entry" >> "${SPOOL}/index.jsonl"

    log "Created: $gif_id (${w}x${h}, ${gif_size}B, ${NUM_FRAMES}frames)"
    rm -rf "$tmp"
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
