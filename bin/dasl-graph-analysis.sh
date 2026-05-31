#!/usr/bin/env bash
# Graph analysis runner for DASL harnesses
# Called by pipelight graph-analysis pipeline
# Uses cargo-vendormod to analyze dependency graphs

set -euo pipefail

CARGO_VM="${1:-/home/mdupont/projects/cargo-clean/tools/cargo-vendormod}"
DASL_HARNESSES="${2:-/home/mdupont/dasl/dasl-testing/harnesses}"

echo "=== Graph Analysis: DASL harness dependency graphs ==="

for h in serde_ipld_dagcbor libipld n0_dasl; do
    echo "--- $h ---"
    outdir="/tmp/graph-$h"
    mkdir -p "$outdir"
    if nix shell "$CARGO_VM#cargo-vendormod" -c graph build \
        -w "$DASL_HARNESSES/$h" \
        -o "$outdir" \
        --include-dev --include-build 2>&1; then
        if [ -f "$outdir/graph.json" ]; then
            nodes=$(jq -r '(.total_nodes // (.nodes | length))' "$outdir/graph.json" 2>/dev/null || echo 0)
            edges=$(jq -r '(.total_edges // (.edges | length))' "$outdir/graph.json" 2>/dev/null || echo 0)
            echo "  $nodes nodes, $edges edges"
        else
            echo "  (no graph.json)"
        fi
    else
        echo "  (graph build failed)"
    fi
done

echo "=== Global dependency graph ==="
if nix build "$CARGO_VM#global-graph" --no-link --print-build-logs 2>&1; then
    outpath=$(nix build "$CARGO_VM#global-graph" --no-link --print-out-paths 2>/dev/null)
    if [ -n "$outpath" ] && [ -f "$outpath/global_graph.json" ]; then
        nodes=$(jq -r '(.nodes | length)' "$outpath/global_graph.json" 2>/dev/null || echo 0)
        edges=$(jq -r '(.edges | length)' "$outpath/global_graph.json" 2>/dev/null || echo 0)
        echo "  Global: $nodes nodes, $edges edges"
    else
        echo "  (global graph n/a)"
    fi
else
    echo "  (global graph build failed)"
fi

echo "  -> Graph analysis complete"
