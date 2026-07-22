#!/usr/bin/env bash
# svg2anim-queue.sh — Queue SVGs for batch GIF/PNG rendering
#
# Scans a list of SVG paths, deduplicates by content hash, filters out
# non-animated/non-JS SVGs, and writes job files for svg2anim-worker.sh.
#
# Usage:
#   ./scripts/svg2anim-queue.sh [ARISTO_LIST] [JOBS_DIR]
#
# Arguments:
#   ARISTO_LIST  Path to newline-delimited SVG list (default: ~/aristotle-results/all_svg.txt)
#   JOBS_DIR     Directory to write job files (default: /srv/kant/svg2anim-jobs)
#
# Environment:
#   QUEUE_DEDUP  If set to 0, skip content-hash deduplication
#
# Job file format:
#   Each job file is named by the first 16 chars of SHA256(content).
#   The file contents are the absolute source path.
#
# Output:
#   Prints "Queued N unique animated SVG jobs" on completion.
#
# Notes:
#   - Static SVGs (no <animate>, <animateTransform>, <animateMotion>,
#     <set>, <script>, or javascript:) are skipped and NOT queued.
#   - Relative paths in ARISTO_LIST starting with ./ are resolved
#     against the directory containing ARISTO_LIST.
#   - Requires: bash 4+, coreutils, grep
set -euo pipefail

ARISTO_LIST="${1:-${ARISTO_LIST:-$HOME/aristotle-results/all_svg.txt}}"
SPOOL="${2:-${JOBS_DIR:-/srv/kant/svg2anim-jobs}}"
DEDUP="${QUEUE_DEDUP:-1}"

mkdir -p "$SPOOL"

if [ ! -f "$ARISTO_LIST" ]; then
    echo "ERROR: ARISTO_LIST not found: $ARISTO_LIST" >&2
    exit 1
fi

aristo_dir="$(cd "$(dirname "$ARISTO_LIST")" && pwd -P)"
declare -A seen
count=0

while IFS= read -r src; do
    [ -n "$src" ] || continue
    [[ "$src" == *.svg ]] || continue

    # Resolve relative paths
    if [[ "$src" == ./* ]]; then
        src="$aristo_dir/${src#./}"
    elif [[ "$src" != /* ]]; then
        src="$aristo_dir/$src"
    fi

    [ -f "$src" ] || continue

    # Content-hash dedup
    if [ "$DEDUP" -eq 1 ]; then
        h=$(sha256sum "$src" | cut -c1-16)
        if [[ -n "${seen[$h]:-}" ]]; then
            continue
        fi
        seen[$h]=1
    else
        h=$(basename "$src" .svg | tr -cd '[:alnum:]_' | cut -c1-16)
    fi

    # Skip static SVGs
    if ! grep -qiE '<(animate|animateTransform|animateMotion|set)[> ]' "$src" && \
       ! grep -qiE '<script[> ]|javascript:' "$src"; then
        continue
    fi

    echo "$src" > "$SPOOL/$h"
    count=$((count + 1))
done < "$ARISTO_LIST"

echo "Queued $count unique animated SVG jobs to $SPOOL"
