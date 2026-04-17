#!/usr/bin/env bash
set -e
ANNOTATE="$(dirname "$0")/zkperf/target/debug/cargo-zkperf"
cd "$(dirname "$0")"

for d in \
  src \
  zkperf/src \
  zkperf/zkperf-witness/src \
  zkperf/cargo-zkperf/src \
  plugins/erdfa-dasl/src \
  plugins/erdfa-sheaf/src \
  plugins/zos-pastebin/src \
  plugins/zos-circuit-optimizer/src \
  erdfa-canonical/zos-plugin-erdfa/src \
  erdfa-clean/src; do
  [ -d "$d" ] && echo "=== $d ===" && "$ANNOTATE" annotate "$d"
done
