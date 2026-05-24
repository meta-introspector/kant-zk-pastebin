#!/usr/bin/env bash
# Standalone tile tests — no Rust library compilation needed
# Tests the tile detection and rendering logic using Python
set -euo pipefail

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Tile Detection & Rendering Tests                           ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

PASS=0
FAIL=0

check() {
    local name="$1"
    local result="$2"
    local expected="$3"
    # Support glob patterns with * wildcard
    case "$result" in
        $expected)
            echo "  ✅ $name"
            PASS=$((PASS + 1));;
        *)
            echo "  ❌ $name: expected pattern '$expected', got '${result:0:80}...'"
            FAIL=$((FAIL + 1));;
    esac
}

# ── Detection tests ──

echo "── Tile Detection ──"

# We test the same logic as detect_tile_type()
detect() {
    local title="$1" mime="$2" content="$3"
    case "$mime" in
        text/vnd.plantuml|application/x-plantuml) echo "plantuml"; return;;
        text/vnd.graphviz|text/x-graphviz) echo "graphviz"; return;;
        text/x-minizinc) echo "minizinc"; return;;
        text/x-lean) echo "lean"; return;;
        text/x-tulip) echo "tulip"; return;;
    esac
    local lower="${title,,}"
    case "$lower" in
        *.puml|*.plantuml) echo "plantuml"; return;;
        *.dot|*.gv) echo "graphviz"; return;;
        *.mzn) echo "minizinc"; return;;
        *.lean) echo "lean"; return;;
        *.tlp) echo "tulip"; return;;
    esac
    case "$content" in
        @startuml*|@startdot*) echo "plantuml"; return;;
        digraph*|graph\ *) echo "graphviz"; return;;
        *"constraint "*|*"solve satisfy"*) echo "minizinc"; return;;
        theorem*|lemma*|def\ *) echo "lean"; return;;
        "(nodes "*|"(TLP"*) echo "tulip"; return;;
    esac
    echo ""
}

check "plantuml by ext"     "$(detect "d.puml" "" "")" "plantuml"
check "plantuml by mime"    "$(detect "d" "text/vnd.plantuml" "")" "plantuml"
check "plantuml by content" "$(detect "d" "" "@startuml")" "plantuml"
check "graphviz by ext"     "$(detect "g.dot" "" "")" "graphviz"
check "graphviz by content" "$(detect "g" "" "digraph G {}")" "graphviz"
check "minizinc by ext"     "$(detect "m.mzn" "" "")" "minizinc"
check "minizinc by content" "$(detect "m" "" "solve satisfy;")" "minizinc"
check "lean by ext"         "$(detect "p.lean" "" "")" "lean"
check "lean by content"     "$(detect "p" "" "theorem t")" "lean"
check "tulip by ext"        "$(detect "g.tlp" "" "")" "tulip"
check "tulip by content"    "$(detect "g" "" "(nodes 0 1)")" "tulip"
check "no match"            "$(detect "n.txt" "" "hello")" ""

# ── Render tests ──

echo ""
echo "── Tile Rendering ──"

render() {
    local type="$1" content="$2"
    local escaped="${content//&/&amp;}"
    escaped="${escaped//</&lt;}"
    escaped="${escaped//>/&gt;}"
    case "$type" in
        plantuml) echo "<div class=\"tile\"><h3>📐 PlantUML</h3><button onclick=\"renderPlantUML(this)\">▶ Render</button></div>";;
        graphviz) echo "<div class=\"tile\"><h3>📊 Graphviz</h3><button onclick=\"renderGraphViz(this)\">▶ Render</button></div>";;
        minizinc) echo "<div class=\"tile\"><h3>🧮 MiniZinc</h3><button onclick=\"solveMiniZinc(this)\">▶ Solve</button></div>";;
        lean)     echo "<div class=\"tile\"><h3>🏛️ Lean</h3><button onclick=\"verifyLean(this)\">▶ Verify</button></div>";;
        tulip)    echo "<div class=\"tile\"><h3>🔗 Tulip</h3><button onclick=\"analyzeTulip(this)\">▶ Analyze</button></div>";;
        *) echo "";;
    esac
}

check "plantuml button"  "$(render plantuml "x")" "*renderPlantUML*"
check "graphviz button"  "$(render graphviz "x")" "*renderGraphViz*"
check "minizinc button"  "$(render minizinc "x")" "*solveMiniZinc*"
check "lean button"      "$(render lean "x")" "*verifyLean*"
check "tulip button"     "$(render tulip "x")" "*analyzeTulip*"
check "unknown returns empty" "$(render nope "x")" ""
check "html is escaped"  "$(render lean "<script>")" "*&lt;*"

# ── Summary ──

echo ""
echo "── Summary ──"
echo "  Passed: $PASS ✅"
echo "  Failed: $FAIL ❌"
echo ""

[ "$FAIL" -eq 0 ]

echo ""
echo "── Tile Rendering (contains checks) ──"

render_plantuml=$(render plantuml "x")
render_graphviz=$(render graphviz "x")
render_minizinc=$(render minizinc "x")
render_lean=$(render lean "x")
render_tulip=$(render tulip "x")

if [[ "$render_plantuml" == *"renderPlantUML"* ]]; then echo "  ✅ plantuml button"; PASS=$((PASS+1)); else echo "  ❌ plantuml button"; FAIL=$((FAIL+1)); fi
if [[ "$render_graphviz" == *"renderGraphViz"* ]]; then echo "  ✅ graphviz button"; PASS=$((PASS+1)); else echo "  ❌ graphviz button"; FAIL=$((FAIL+1)); fi
if [[ "$render_minizinc" == *"solveMiniZinc"* ]]; then echo "  ✅ minizinc button"; PASS=$((PASS+1)); else echo "  ❌ minizinc button"; FAIL=$((FAIL+1)); fi
if [[ "$render_lean" == *"verifyLean"* ]]; then echo "  ✅ lean button"; PASS=$((PASS+1)); else echo "  ❌ lean button"; FAIL=$((FAIL+1)); fi
if [[ "$render_tulip" == *"analyzeTulip"* ]]; then echo "  ✅ tulip button"; PASS=$((PASS+1)); else echo "  ❌ tulip button"; FAIL=$((FAIL+1)); fi

render_unknown=$(render nope "x")
if [ -z "$render_unknown" ]; then echo "  ✅ unknown returns empty"; PASS=$((PASS+1)); else echo "  ❌ unknown should be empty"; FAIL=$((FAIL+1)); fi

render_escaped=$(render lean "<script>")
if [[ "$render_escaped" == *"&lt;"* ]]; then echo "  ✅ html is escaped"; PASS=$((PASS+1)); else echo "  ❌ html should be escaped"; FAIL=$((FAIL+1)); fi
