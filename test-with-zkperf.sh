#!/usr/bin/env bash
# Test using zkperf's actual tools

set -e

echo "=== zkPerf Coverage Testing ==="
echo ""

cd zkperf

# Build zkperf
echo "📦 Building zkperf..."
nix develop -c cargo build

# Run cargo-zkperf audit
echo ""
echo "🔍 Running cargo-zkperf audit..."
nix develop -c cargo run -p cargo-zkperf -- audit ../src > ../zkperf-audit.txt

# Generate report
echo ""
echo "📊 Generating zkperf report..."
nix develop -c cargo run -p cargo-zkperf -- report ../src > ../zkperf-report.json

cd ..

echo ""
echo "✅ zkPerf coverage complete"
echo ""
echo "Reports:"
echo "  zkperf-audit.txt   - Audit results"
echo "  zkperf-report.json - JSON report"
echo ""

# Show summary
if [ -f zkperf-report.json ]; then
    echo "Summary:"
    cat zkperf-report.json | head -20
fi
