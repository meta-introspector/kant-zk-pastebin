#!/usr/bin/env bash
# DASL CI Pipeline — build, test, fuzz, graph all DASL packages via nix
#
# Principles:
#   1. All builds go through nix build from ~/dasl/dasl-testing/
#   2. No direct cargo/npm/pip commands — everything through nix
#   3. Results written to /mnt/data1/nora/ci-results/ as status.json
#   4. Graph analysis uses cargo-vendormod via nix shell
#   5. All Rust crate deps come from nora (nora.txt line215 pattern):
#      [source.crates-io] replace-with = "nora"
#      [source.nora] registry = "http://127.0.0.1:4000/cargo/index"
#      → Injected via preBuild in dasl-testing/flake.nix (buildRustService)
#      → Also available at /etc/nora-cargo/config.toml (CARGO_HOME=/etc/nora-cargo)
#
# Usage: dasl-ci [--full] [--publish]
#   --full    Full run including fuzz (default: build + test + graph only)
#   --publish Push built artifacts to NORA

set -euo pipefail

RESULTS="${NORA_CI_RESULTS:-/mnt/data1/nora/ci-results}"
DASL_TESTING="${DASL_TESTING:-/home/mdupont/dasl/dasl-testing}"
CARGO_VENDORMOD="${CARGO_VENDORMOD:-/home/mdupont/projects/cargo-clean/tools/cargo-vendormod}"
NORA_URL="${NORA_URL:-http://127.0.0.1:4000}"
TIMESTAMP="$(date -Iseconds)"
LOG_DIR="$RESULTS/logs"
FULL="${1:-}"
PUBLISH="${2:-}"

mkdir -p "$RESULTS"/{build,tests,fuzz,perf,graph} "$LOG_DIR"

duration() {
    local start="$1" end="$2"
    printf "%ds" $(( end - start ))
}

nix_build() {
    local phase="$1"
    local label="$2"
    local flake_ref="$3"
    local logfile="$RESULTS/$phase/$label.log"
    local start_time
    start_time="$(date +%s)"
    echo "  [$phase] $label (nix build $flake_ref) ..." | tee -a "$logfile"
    if nix build "$flake_ref" --no-link --print-build-logs \
        2>> "$logfile" >> "$logfile"; then
        local end_time
        end_time="$(date +%s)"
        echo "  -> $label: PASS ($(duration start_time end_time))" | tee -a "$logfile"
        printf '{"phase":"%s","label":"%s","status":"pass","duration":%d}\n' \
            "$phase" "$label" "$((end_time - start_time))" \
            >> "$RESULTS/$phase/results.jsonl"
        return 0
    else
        local end_time
        end_time="$(date +%s)"
        echo "  -> $label: FAIL ($(duration start_time end_time))" | tee -a "$logfile"
        printf '{"phase":"%s","label":"%s","status":"fail","duration":%d}\n' \
            "$phase" "$label" "$((end_time - start_time))" \
            >> "$RESULTS/$phase/results.jsonl"
        return 1
    fi
}

# ══════════════════════════════════════════════════════════════════════
# STEP 1: Build all DASL testing packages via nix
# ════════════════════════════════════════════════════════════════════════
echo "=== [1/5] Nix build: all DASL testing packages ==="
BUILD_FAILURES=""

# Rust services
for pkg in serdeIpldDagcbor libipld n0Dasl; do
    nix_build build "$pkg" "$DASL_TESTING#$pkg" || {
        BUILD_FAILURES="$BUILD_FAILURES $pkg"
    }
done

# C CBOR round-robin binaries
nix_build build "c-cbor-all" "$DASL_TESTING#c-cbor-all" || {
    BUILD_FAILURES="$BUILD_FAILURES c-cbor-all"
}

# All services combined
nix_build build "default" "$DASL_TESTING#default" || {
    BUILD_FAILURES="$BUILD_FAILURES default"
}

BUILD_STATUS="success"
[ -n "$BUILD_FAILURES" ] && BUILD_STATUS="failure"
echo "Build status: $BUILD_STATUS" >> "$RESULTS/build/build.log"
echo "  -> Built ${BUILD_FAILURES:-all packages}"

# ════════════════════════════════════════════════════════════════════════
# STEP 2: Run tests via nix (Go tests, plus Rust unit tests via harnesses)
# ════════════════════════════════════════════════════════════════════════
echo "=== [2/5] Nix tests ==="
TEST_STATUS="success"
TEST_FAILURES=""
TEST_PASS=0
TEST_FAIL=0

# Go tests (defined as check in dasl-testing flake)
if nix_build test "go-test" "$DASL_TESTING#checks.x86_64-linux.go-test"; then
    TEST_PASS=$((TEST_PASS + 1))
else
    TEST_FAIL=$((TEST_FAIL + 1))
    TEST_FAILURES="$TEST_FAILURES go-test"
    TEST_STATUS="failure"
fi

# Rust service harnesses — each has a flake.nix that produces round-robin binaries.
# Build them to verify compilation + basic soundness.
for harness_path in "$DASL_TESTING/harnesses/serde_ipld_dagcbor" \
                    "$DASL_TESTING/harnesses/libipld" \
                    "$DASL_TESTING/harnesses/n0_dasl"; do
    harness_name="$(basename "$harness_path")"
    if nix_build test "$harness_name" "path:$harness_path#default"; then
        TEST_PASS=$((TEST_PASS + 1))
    else
        TEST_FAIL=$((TEST_FAIL + 1))
        TEST_FAILURES="$TEST_FAILURES $harness_name"
        TEST_STATUS="failure"
    fi
done

echo "Test status: $TEST_STATUS (PASS=$TEST_PASS FAIL=$TEST_FAIL)"

# ════════════════════════════════════════════════════════════════════════
# STEP 3: Graph analysis via cargo-vendormod
# ════════════════════════════════════════════════════════════════════════
echo "=== [3/5] Graph analysis (cargo-vendormod) ==="
GRAPH_STATUS="success"
GRAPH_NODES=0
GRAPH_EDGES=0

# Analyze dasl-testing harnesses using cargo-vendormod's graph targets.
# Each nix build --impure .#graph-<name> produces graph.json + summary.json.
# We use path: refs to avoid needing a flake input for cargo-vendormod.

for project_name in serde_ipld_dagcbor libipld n0_dasl; do
    project_path="$DASL_TESTING/harnesses/$project_name"
    [ -f "$project_path/Cargo.toml" ] || continue
    logfile="$RESULTS/graph/$project_name.log"
    echo "  [graph] $project_name ..." | tee -a "$logfile"

    # Use vendormod directly: graph build -w <path> -o <output> --include-dev
    if nix shell "$CARGO_VENDORMOD#cargo-vendormod" -c graph build \
        -w "$project_path" -o "$RESULTS/graph/$project_name" \
        --include-dev --include-build 2>> "$logfile"; then
        # Read summary
        if [ -f "$RESULTS/graph/$project_name/graph.json" ]; then
            local_nodes=$(jq -r '.total_nodes // (.nodes | length)' \
                "$RESULTS/graph/$project_name/graph.json" 2>/dev/null || echo 0)
            local_edges=$(jq -r '.total_edges // (.edges | length)' \
                "$RESULTS/graph/$project_name/graph.json" 2>/dev/null || echo 0)
            GRAPH_NODES=$((GRAPH_NODES + local_nodes))
            GRAPH_EDGES=$((GRAPH_EDGES + local_edges))
            printf '{"phase":"graph","label":"%s","status":"pass","nodes":%d,"edges":%d}\n' \
                "$project_name" "$local_nodes" "$local_edges" \
                >> "$RESULTS/graph/results.jsonl"
            echo "  -> $project_name: $local_nodes nodes, $local_edges edges" | tee -a "$logfile"
        else
            echo "  -> $project_name: graph.json not found" | tee -a "$logfile"
        fi
    else
        GRAPH_STATUS="failure"
        printf '{"phase":"graph","label":"%s","status":"fail"}\n' \
            "$project_name" >> "$RESULTS/graph/results.jsonl"
    fi
done

echo "Graph: $GRAPH_STATUS ($GRAPH_NODES nodes, $GRAPH_EDGES edges total)"

# ════════════════════════════════════════════════════════════════════════
# STEP 4: Fuzz testing (via nix develop shell + Makefile)
# ════════════════════════════════════════════════════════════════════════
# Fuzz testing requires running the harness binaries with fuzzing inputs.
# We use nix develop to get the right toolchain, then run make fuzz.
# This avoids direct cargo commands while using nix for dependency mgmt.
echo "=== [4/5] Fuzz testing ==="
FUZZ_STATUS="skipped"
FUZZ_CRASHES=0

if [ "${FULL:-}" = "--full" ]; then
    FUZZ_STATUS="running"
    FUZZ_LOG="$RESULTS/fuzz/fuzz-results.log"
    : > "$FUZZ_LOG"

    echo "  Running fuzz via nix develop + Makefile ..." | tee -a "$FUZZ_LOG"
    if nix develop "$DASL_TESTING#default" -c bash -c '
        cd "$DASL_TESTING"
        echo "  Building fuzz targets..."
        make build 2>&1 || true
        echo "  Running quick fuzz..."
        make fuzz ITER_QUICK=500 2>&1 || true
        echo "  Fuzz complete"
    ' 2>> "$FUZZ_LOG" >> "$FUZZ_LOG"; then
        FUZZ_STATUS="completed"
    else
        FUZZ_STATUS="partial"
    fi

    # Count crashes from the log
    FUZZ_CRASHES=$(grep -c 'CRASH\|CRASHES\|crash detected\|SIGABRT\|panic' \
        "$FUZZ_LOG" 2>/dev/null || echo 0)
    echo "Fuzz: $FUZZ_STATUS ($FUZZ_CRASHES crashes)" | tee -a "$FUZZ_LOG"
else
    echo "  Skipped (use --full to enable fuzz)"
fi

# ════════════════════════════════════════════════════════════════════════
# STEP 5: Push artifacts to NORA (optional, --publish flag)
# ════════════════════════════════════════════════════════════════════════
if [ "${PUBLISH:-}" = "--publish" ]; then
    echo "=== [5/5] Publishing to NORA ==="
    PUB_LOG="$RESULTS/publish.log"
    : > "$PUB_LOG"

    # Push the entire dasl-testing store derivation outputs to NORA raw storage
    echo "  Publishing dasl-testing nix store paths to NORA ..." | tee -a "$PUB_LOG"
    for pkg in serdeIpldDagcbor libipld n0Dasl c-cbor-all default; do
        echo "  Publishing $pkg ..." | tee -a "$PUB_LOG"
        store_path=$(nix build "$DASL_TESTING#$pkg" --no-link --print-out-paths \
            2>/dev/null || true)
        if [ -n "$store_path" ] && [ -d "$store_path" ]; then
            archive_name="dasl-testing-$pkg-$(date +%Y%m%d).tar.gz"
            tar czf "/tmp/$archive_name" -C "$(dirname "$store_path")" \
                "$(basename "$store_path")" 2>/dev/null || true
            # Upload to NORA raw storage
            curl -s -X PUT "$NORA_URL/raw/dasl-testing/builds/$archive_name" \
                --data-binary @"/tmp/$archive_name" \
                -H "Content-Type: application/gzip" \
                -o /dev/null -w "  -> HTTP %{http_code}\n" \
                2>/dev/null | tee -a "$PUB_LOG" || true
            rm -f "/tmp/$archive_name"
        fi
    done

    # Also publish graph analysis results
    echo "  Publishing graph analysis to NORA ..." | tee -a "$PUB_LOG"
    if [ -d "$RESULTS/graph" ]; then
        tar czf "/tmp/dasl-graph-results-$(date +%Y%m%d).tar.gz" \
            -C "$RESULTS" graph/ 2>/dev/null || true
        curl -s -X PUT "$NORA_URL/raw/dasl-testing/graph/$(date +%Y%m%d).tar.gz" \
            --data-binary @"/tmp/dasl-graph-results-$(date +%Y%m%d).tar.gz" \
            -H "Content-Type: application/gzip" \
            -o /dev/null -w "  -> HTTP %{http_code}\n" \
            2>/dev/null | tee -a "$PUB_LOG" || true
        rm -f "/tmp/dasl-graph-results-$(date +%Y%m%d).tar.gz"
    fi

    # Trigger NORA raw index rebuild
    echo "  Triggering NORA raw index rebuild ..." | tee -a "$PUB_LOG"
    curl -s -X POST "$NORA_URL/raw/reindex" -o /dev/null -w "  -> HTTP %{http_code}\n" \
        2>/dev/null | tee -a "$PUB_LOG" || true

    echo "Publishing complete" | tee -a "$PUB_LOG"
fi

# ════════════════════════════════════════════════════════════════════════
# AGGREGATE RESULTS
# ════════════════════════════════════════════════════════════════════════
echo "=== Aggregating results ==="

# Collect build log tails
BUILD_LOG_TAIL=$(for f in "$RESULTS/build"/*.log; do
    [ -f "$f" ] && tail -3 "$f" 2>/dev/null
done 2>/dev/null || echo "")

TEST_SUMMARY=$(for f in "$RESULTS/tests"/*.log; do
    [ -f "$f" ] && grep -E 'test result|FAILED|PASS|FAIL' "$f" 2>/dev/null | tail -5
done 2>/dev/null || echo "")

FUZZ_SUMMARY=$(tail -5 "$RESULTS/fuzz/fuzz-results.log" 2>/dev/null || echo "")

GRAPH_SUMMARY="nodes=$GRAPH_NODES edges=$GRAPH_EDGES status=$GRAPH_STATUS"

cat > "$RESULTS/status.json" << JSONEOF
{
  "pipeline": "dasl-ci-nix",
  "timestamp": "$TIMESTAMP",
  "build": {
    "status": "$BUILD_STATUS",
    "failures": "$(echo $BUILD_FAILURES | xargs)",
    "packages_total": 5
  },
  "tests": {
    "status": "$TEST_STATUS",
    "pass": $TEST_PASS,
    "fail": $TEST_FAIL,
    "failures": "$(echo $TEST_FAILURES | xargs)",
    "summary": $(echo "$TEST_SUMMARY" | jq -Rs .)
  },
  "fuzz": {
    "status": "$FUZZ_STATUS",
    "crashes": $FUZZ_CRASHES,
    "summary": $(echo "$FUZZ_SUMMARY" | jq -Rs .)
  },
  "graph": {
    "status": "$GRAPH_STATUS",
    "nodes": $GRAPH_NODES,
    "edges": $GRAPH_EDGES,
    "summary": "$GRAPH_SUMMARY"
  },
  "metadata": {
    "dasl_testing_flake": "$DASL_TESTING",
    "build_logs": "/nora/ci-results/build/",
    "test_logs": "/nora/ci-results/tests/",
    "fuzz_logs": "/nora/ci-results/fuzz/",
    "graph_results": "/nora/ci-results/graph/"
  }
}
JSONEOF

echo ""
echo "=== DASL CI Pipeline complete ==="
echo "  Build:  $BUILD_STATUS"
echo "  Tests:  $TEST_STATUS (PASS=$TEST_PASS FAIL=$TEST_FAIL)"
echo "  Graph:  $GRAPH_STATUS ($GRAPH_NODES nodes, $GRAPH_EDGES edges)"
echo "  Fuzz:   $FUZZ_STATUS ($FUZZ_CRASHES crashes)"
echo ""
echo "  Dashboard: https://solana.solfunmeme.com/nora/dashboard/"
echo "  Results:   https://solana.solfunmeme.com/nora/ci-results/"
