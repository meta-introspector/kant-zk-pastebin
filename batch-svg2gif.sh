#!/usr/bin/env bash
# batch-svg2gif.sh — Convert all SVGs in a directory to animated GIFs
# Usage: ./batch-svg2gif.sh [input_dir] [output_dir] [fps]
set -euo pipefail

INPUT_DIR="${1:-.}"
OUTPUT_DIR="${2:-/tmp/svg2gif-output}"
FPS="${3:-5}"
BIN="${SVG2ANIM_FRAMES_BIN:-/mnt/data1/time-2026/06-june/26/svg2anim-frames/target/debug/svg2anim-frames}"

mkdir -p "$OUTPUT_DIR"

count=0
fail=0
pass=0

for svg in "$INPUT_DIR"/*.svg; do
    [ -f "$svg" ] || continue
    count=$((count + 1))
    base=$(basename "$svg" .svg)
    out="$OUTPUT_DIR/${base}.gif"
    echo "[$count] Converting: $(basename "$svg")"
    if "$BIN" "$svg" --output "$out" --fps "$FPS" 2>&1; then
        size=$(stat -c%s "$out" 2>/dev/null || stat -f%z "$out" 2>/dev/null || echo "0")
        echo "  -> OK: $out ($size bytes)"
        pass=$((pass + 1))
    else
        echo "  -> FAILED"
        fail=$((fail + 1))
    fi
done

echo ""
echo "=== Summary ==="
echo "Total: $count | Passed: $pass | Failed: $fail"
echo "Output: $OUTPUT_DIR"
