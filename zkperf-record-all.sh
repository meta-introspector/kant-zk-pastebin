#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"

ANNOTATE="zkperf/target/debug/cargo-zkperf"
PERF_REC="perf record -g -e cycles:u -c 1000"
RECORDINGS="perf-recordings"
mkdir -p "$RECORDINGS"

# 1. Annotate all src dirs
./zkperf-annotate-all.sh

# 2. Build all bins
echo "=== building ==="
nix develop --command cargo build 2>&1 | tail -3

# 3. Perf record each binary
BINS=(
  kantpaste
  js_parser
  js_interpreter
  js_deobfuscate
  html_parser
  css_parser
  website_ingest
)

for bin in "${BINS[@]}"; do
  out="$RECORDINGS/${bin}.perf.data"
  echo "=== perf record $bin ==="
  nix develop --command bash -c \
    "$PERF_REC -o $out -- cargo run --bin $bin -- --help 2>/dev/null || true" \
    2>&1 | tail -3
  [ -f "$out" ] && echo "  → $out ($(du -sh $out | cut -f1))"
done

# 4. Run cargo-zkperf report against perf data
echo "=== generating zkperf report ==="
nix develop --command "$ANNOTATE" report src > zkperf-report.json
echo "  → zkperf-report.json"
