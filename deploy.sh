#!/usr/bin/env bash
set -e

echo "=== Deploying Kant Pastebin with Plugins ==="
cargo build 2>&1

STORE_PATH=$(echo "./target/debug")
BINARY="$STORE_PATH/bin/kant-pastebin"
[ -x "$BINARY" ] || BINARY="./target/debug/kant-pastebin"
[ -x "$BINARY" ] || { echo "Binary not found at $BINARY"; exit 1; }

echo "Built: $BINARY"
echo ""
echo "To run manually:"
echo "  export DAGCBOR_TILES_PATH=/mnt/data1/time-2026/02-february/22/dasl/dasl-testing/sheaf/tiles/dagcbor_tiles.html"
echo "  RUST_LOG=info $BINARY"
echo ""
echo "Or install systemd service:"
cat > kant-pastebin.service << UNIT
[Unit]
Description=Kant Pastebin
After=network.target
[Service]
Type=simple
WorkingDirectory=$(pwd)
ExecStart=$BINARY
Restart=always
RestartSec=10
Environment=BIND_ADDR=127.0.0.1:8090
Environment=UUCP_SPOOL=/mnt/data1/spool/uucp/pastebin
Environment=DAGCBOR_TILES_PATH=/mnt/data1/time-2026/02-february/22/dasl/dasl-testing/sheaf/tiles/dagcbor_tiles.html
Environment=FLAMEGRAPH_MAX_TILES=100
Environment=RUST_LOG=info
[Install]
WantedBy=default.target
UNIT
echo "  Systemd: cp kant-pastebin.service ~/.config/systemd/user/ && systemctl --user daemon-reload && systemctl --user restart kant-pastebin"
echo ""
echo "Test: curl -s http://127.0.0.1:8090/ | head -5"
echo ""
echo "=== Plugin Endpoints ==="
echo "  POST /plugin/flamegraph?action=generate    - Generate flamegraph SVG"
echo "  POST content: folded stack data"
echo "  GET  /plugin/flamegraph/help               - Interactive HTML form"
echo "  GET  /plugin/dasl_testing/help             - Dashboard overview"
echo "  GET  /plugin/dasl_testing/demo             - Full ECharts demo"
echo "  POST /plugin/dasl_testing/lattice          - Generate complexity lattice"
echo "  GET  /plugin/midi/help                     - MIDI tile generator"
echo "  GET  /plugin/plantuml/help                 - PlantUML diagram viewer"
echo "  GET  /plugin/plugin_browser               - Plugin directory"
echo "  POST /plugin/plocate_search?action=search&q=parquet  - Fast file search via plocate"
echo "  POST /plugin/plocate_search?action=brief&q=decode    - Brief filename-only search"
echo "  GET  /plugin/decl_tile/help               - Interactive syn AST tree viewer"
echo "  POST /plugin/perf_annotations/annotate    - Profiling annotation overlays"
echo "  POST /plugin/decl_patterns_analyzer/analyze - Cross-project syn pattern analysis"
echo "  POST /plugin/decl_patterns_analyzer/brief   - Brief pattern analysis summary"
echo "  GET  /plugin/decl_patterns_analyzer/help    - Interactive analysis form"
echo ""
echo ""
echo "  # Plugin Browser"
echo "  curl http://127.0.0.1:8090/plugin/plugin_browser         # List all plugins"
echo ""
echo "  # Decl Patterns Analyzer"
echo "  curl http://127.0.0.1:8090/plugin/decl_patterns_analyzer/help | head -5
  curl -X POST -d 'forge_domain=../../forgecode/crates/forge_domain/src/decls&forge_main=../../forgecode/crates/forge_main/src/decls&forge_app=../../forgecode/crates/forge_app/src/decls&pi_agent=../../pi_agent_rust/pi/src/decls' http://127.0.0.1:8090/plugin/decl_patterns_analyzer/analyze | head -5"
echo "  curl 'http://127.0.0.1:8090/plugin/plocate_search?action=search&q=parquet' | head -3"
