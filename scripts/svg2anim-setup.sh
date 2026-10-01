#!/usr/bin/env bash
# scripts/svg2anim-setup.sh — Setup the SVG→GIF/PNG batch pipeline.
#
# Documents current toolchain, verifies dependencies, creates the
# service directories, and optionally queues animated SVGs from
# ~/aristotle-results/all_svg.txt.
#
# Usage:
#   ./scripts/svg2anim-setup.sh [list] [jobs] [results] [worker] [queue]
#
# Arguments:
#   list     Newline-delimited SVG list
#            default: ~/aristotle-results/all_svg.txt
#   jobs     Job file directory
#            default: /srv/kant/svg2anim-jobs
#   results  Render output directory
#            default: /srv/kant/svg2anim-results
#   worker   Worker script path
#            default: scripts/svg2anim-worker.sh
#   queue    Queue script path
#            default: scripts/svg2anim-queue.sh
#
# Environment:
#   SVG2ANIM_FRAMES  Path to svg2anim-frames binary
#                    default: /mnt/data1/time-2026/06-june/26/svg2anim-frames/target/release/svg2anim-frames
#   SVG2ANIM_CONVERT Path to ImageMagick convert binary
#                    default: convert
#   QUEUE_DEDUP      Set to 0 to disable content-hash dedup
#                    default: 1
#
# Directories:
#   /srv/kant/svg-spool/svg2anim-jobs    worker job files
#   /srv/kant/svg-spool/svg2anim-results rendered GIFs and PNGs
#
# Notes:
#   - Static SVGs are skipped during queueing unless QUEUE_ALL=1.
#   - Worker watches jobs dir, renders GIF for animated SVGs,
#     PNG for static SVGs (or when svg2anim-frames is unavailable).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"

ARISTO_LIST="${1:-${ARISTO_LIST:-$HOME/aristotle-results/all_svg.txt}}"
JOBS_DIR="${2:-${JOBS_DIR:-/srv/kant/svg2anim-jobs}}"
RESULTS_DIR="${3:-${RESULTS_DIR:-/srv/kant/svg2anim-results}}"
WORKER="${4:-${WORKER:-$SCRIPT_DIR/svg2anim-worker.sh}}"
QUEUE="${5:-${QUEUE:-$SCRIPT_DIR/svg2anim-queue.sh}}"

SVG2ANIM_FRAMES="${SVG2ANIM_FRAMES:-/mnt/data1/time-2026/06-june/26/svg2anim-frames/target/release/svg2anim-frames}"
CONVERT_BIN="${SVG2ANIM_CONVERT:-convert}"
DEDUP="${QUEUE_DEDUP:-1}"
QUEUE_ALL="${QUEUE_ALL:-0}"

log() { echo "[svg2anim-setup] $(date -u +%Y-%m-%dT%H:%M:%SZ) $*"; }

check_deps() {
    log "Checking dependencies..."
    local missing=0

    if [ ! -x "$WORKER" ]; then
        log "WARN: worker script missing or not executable: $WORKER"
        missing=$((missing + 1))
    fi

    if [ ! -x "$QUEUE" ]; then
        log "WARN: queue script missing or not executable: $QUEUE"
        missing=$((missing + 1))
    fi

    if [ ! -x "$SVG2ANIM_FRAMES" ]; then
        log "WARN: svg2anim-frames binary not found at $SVG2ANIM_FRAMES"
        log "       Animated SVGs will fail unless this is installed."
    else
        log "OK:  svg2anim-frames at $SVG2ANIM_FRAMES"
    fi

    if ! command -v "$CONVERT_BIN" >/dev/null 2>&1; then
        log "WARN: ImageMagick convert not found at $CONVERT_BIN"
        log "       Static SVGs will fail unless this is installed."
    else
        log "OK:  convert at $(command -v "$CONVERT_BIN")"
    fi

    if [ ! -f "$ARISTO_LIST" ]; then
        log "WARN: ARISTO_LIST not found: $ARISTO_LIST"
        missing=$((missing + 1))
    else
        log "OK:  list at $ARISTO_LIST ($(wc -l < "$ARISTO_LIST") lines)"
    fi

    python3 -c 'import hashlib, re, os' 2>/dev/null && \
        log "OK:  python3 available (used by check_svg_anim.py)" || \
        log "WARN: python3 not available for animation detection fallback"

    return $missing
}

create_dirs() {
    log "Creating directories..."
    mkdir -p "$JOBS_DIR" "$RESULTS_DIR"
    log "OK:  jobs    -> $JOBS_DIR"
    log "OK:  results -> $RESULTS_DIR"
}

queue_animated() {
    log "Queueing animated SVGs from: $ARISTO_LIST"

    if [ ! -f "$ARISTO_LIST" ]; then
        log "SKIP: ARISTO_LIST not found"
        return 0
    fi

    if [ "$QUEUE_ALL" = "1" ]; then
        log "QUEUE_ALL=1: queuing all SVGs, animation detection skipped"
    fi

    export JOBS_DIR="$JOBS_DIR"
    export QUEUE_DEDUP="$DEDUP"
    export QUEUE_ALL="$QUEUE_ALL"

    if ! bash "$QUEUE" "$ARISTO_LIST" "$JOBS_DIR"; then
        log "ERROR: queue script failed"
        return 1
    fi

    local count
    count=$(find "$JOBS_DIR" -type f | wc -l)
    log "OK:  queued $count jobs"
}

show_service_examples() {
    log "Systemd service: ${WORKER}"
    cat <<'EOF'
# Example systemd unit: /etc/systemd/system/svg2anim-worker.service
[Unit]
Description=SVG to Animated GIF/PNG Worker
After=network.target

[Service]
Type=simple
User=kant
Group=kant
ExecStart=/usr/bin/bash /mnt/data1/kant/pastebin/scripts/svg2anim-worker.sh
Restart=always
RestartSec=10
Environment=UUCP_SPOOL=/srv/kant/svg-spool
Environment=SVG2ANIM_FRAMES_BIN=/mnt/data1/time-2026/06-june/26/svg2anim-frames/target/release/svg2anim-frames
Environment=SVG2ANIM_FPS=5
Environment=SVG2ANIM_MAX_WIDTH=1920
Environment=SVG2ANIM_MAX_HEIGHT=1200
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
}

show_tmpfiles_examples() {
    log "Tmpfiles.d rules:"
    cat <<'EOF'
# /etc/tmpfiles.d/svg2anim.conf
d /srv/kant/svg-spool 0755 kant kant -
d /srv/kant/svg-spool/svg2anim-jobs 0755 kant kant -
d /srv/kant/svg-spool/svg2anim-results 0755 kant kant -
EOF

    log "Nix systemd tmpfiles.rules (pastebin-system.nix):"
    cat <<'EOF'
systemd.tmpfiles.rules = [
  "d /srv/kant/svg-spool 0755 kant kant -"
  "d /srv/kant/svg-spool/svg2anim-jobs 0755 kant kant -"
  "d /srv/kant/svg-spool/svg2anim-results 0755 kant kant -"
];
EOF
}

main() {
    log "=== svg2anim pipeline setup ==="
    log "Repo: $REPO_DIR"
    log "List: $ARISTO_LIST"
    log "Jobs: $JOBS_DIR"
    log "Out:  $RESULTS_DIR"
    log "Worker: $WORKER"
    log "Queue: $QUEUE"
    log ""

    check_deps || true
    log ""
    create_dirs
    log ""

    local mode="${1:-}"
    if [ "$mode" = "queue" ] || [ "$mode" = "all" ]; then
        queue_animated
    elif [ -n "$mode" ]; then
        log "Unknown mode: $mode (use: queue|all|docs)"
        exit 2
    else
        log "No mode specified. Available modes: queue, all, docs"
        log "Run with 'queue' to queue animated SVGs."
        log "Run with 'all' to create dirs + queue."
    fi

    log ""
    show_service_examples
    log ""
    show_tmpfiles_examples
    log ""
    log "Done."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
