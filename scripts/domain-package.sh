#!/bin/sh
# Run the domain data skill on this project's own proof corpus.
#
#   sh scripts/domain-package.sh [outdir] [module-prefix]
#
# Step one loads the compiled corpus and writes the scan; step two builds
# the canonical graph, emits the package, reads every file back and fails
# if the graph that comes out is not the graph that went in.
set -e
OUT="${1:-domain/run}"
PREFIX="${2:-RequestProject.Kant.Domain.Model}"
mkdir -p "$OUT"
lake build emitdomain packdomain
lake env ./.lake/build/bin/emitdomain "$OUT/corpus-scan.kant" "$PREFIX"
./.lake/build/bin/packdomain "$OUT/corpus-scan.kant" "$OUT"
