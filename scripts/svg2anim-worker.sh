#!/usr/bin/env bash
set -euo pipefail

SPOOL="${UUCP_SPOOL:-/srv/kant/svg-spool}"
JOBS_DIR="${SPOOL}/svg2anim-jobs"
RESULTS_DIR="${SPOOL}/svg2anim-results"
SVG2TILE_CLI="${SVG2TILE_CLI:-/mnt/data1/kant/pastebin/tools/svg2tile-cli/target/release/svg2tile-cli}"
FPS="${SVG2ANIM_FPS:-5}"
MAX_WIDTH="${SVG2ANIM_MAX_WIDTH:-1920}"
MAX_HEIGHT="${SVG2ANIM_MAX_HEIGHT:-1200}"

mkdir -p "$JOBS_DIR" "$RESULTS_DIR"

log() { echo "[svg2anim-worker] $(date -u +%Y-%m-%dT%H:%M:%SZ) $*"; }

process_svg() {
    local job_file="$1"
    local src
    src=$(cat "$job_file")

    if [ ! -f "$src" ]; then
        log "Source SVG missing: $src"
        return 1
    fi

    local stem
    stem=$(basename "$src" .svg)

    local has_anim=0
    if grep -qiE '<(animate|animateTransform|animateMotion|set)[> ]' "$src" || \
       grep -qiE '<script[> ]|javascript:' "$src"; then
        has_anim=1
    fi

    local ts
    ts=$(date -u +%Y%m%d_%H%M%S)

    if [ "$has_anim" -eq 1 ]; then
        local gif_fn="${ts}_${stem}.gif"
        local gif_path="${RESULTS_DIR}/${gif_fn}"
        log "Anim SVG: $src -> $gif_fn"
        if ! timeout "${SVG2ANIM_TIMEOUT:-60}" "$SVG2TILE_CLI" "$src" --output "$gif_path" --fps "$FPS" --width "$MAX_WIDTH" --height "$MAX_HEIGHT" --max-frames 30 2>&1; then
            log "svg2tile-cli failed for $src"
            return 1
        fi
        log "Created GIF: $gif_fn ($(stat -c%s "$gif_path" 2>/dev/null || stat -f%z "$gif_path" 2>/dev/null)B)"
    else
        local png_fn="${ts}_${stem}.png"
        local png_path="${RESULTS_DIR}/${png_fn}"
        log "Static SVG: $src -> $png_fn"
        if ! "$SVG2TILE_CLI" "$src" --output "$png_path" --width "$MAX_WIDTH" --height "$MAX_HEIGHT" 2>&1; then
            log "svg2tile-cli failed for $src"
            return 1
        fi
        log "Created PNG: $png_fn ($(stat -c%s "$png_path" 2>/dev/null || stat -f%z "$png_path" 2>/dev/null)B)"
    fi
}

log "Worker started, watching $JOBS_DIR"
while true; do
    for job in "$JOBS_DIR"/*; do
        [ -f "$job" ] || continue
        case "$job" in
            *.dead) continue ;;
        esac
        process_svg "$job" && rm -f "$job" || mv "$job" "${job}.dead"
    done
    sleep 5
done
