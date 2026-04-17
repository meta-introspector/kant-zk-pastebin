#!/usr/bin/env bash
# Master test orchestrator - runs all tests and generates unified report

set -e

echo "=== Kant Pastebin - Master Test Suite ==="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Track results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

run_test() {
    local name=$1
    local command=$2
    
    echo -e "${YELLOW}▶${NC} Running: $name"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if eval "$command" > /dev/null 2>&1; then
        echo -e "${GREEN}✅${NC} $name passed"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        echo -e "${RED}❌${NC} $name failed"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

echo "📦 Phase 1: Binary Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
run_test "JS Parser" "cargo run --bin js_parser -- test-fixtures/sample.js"
run_test "JS Interpreter" "cargo run --bin js_interpreter"
run_test "HTML Parser" "cargo run --bin html_parser -- test-fixtures/sample.html"
run_test "CSS Parser" "cargo run --bin css_parser -- test-fixtures/sample.css"
run_test "Test Generator" "cargo run --bin test_generator"
run_test "Website Test" "cargo run --bin website_test"
run_test "Frontend Fuzzer" "cargo run --bin fuzz_frontend"
echo ""

echo "🔌 Phase 2: Plugin Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
run_test "Plugin Suite" "cargo run --bin test_plugins"
echo ""

echo "📊 Phase 3: Comprehensive Coverage"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
run_test "Comprehensive Test" "cargo run --bin comprehensive_test"
echo ""

echo "📈 Phase 4: Report Generation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
run_test "HTML Report" "cargo run --bin generate_html_report"
echo ""

# Combine all JSON reports
echo "📋 Combining reports..."
cat > combined-report.json <<EOF
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "summary": {
    "total_tests": $TOTAL_TESTS,
    "passed": $PASSED_TESTS,
    "failed": $FAILED_TESTS,
    "success_rate": $(echo "scale=2; $PASSED_TESTS * 100 / $TOTAL_TESTS" | bc)
  },
  "test_report": $(cat test-report.json 2>/dev/null || echo '{}'),
  "plugin_report": $(cat plugin-test-report.json 2>/dev/null || echo '{}')
}
EOF

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Final Results"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "Total Tests:  $TOTAL_TESTS"
echo -e "Passed:       ${GREEN}$PASSED_TESTS${NC}"
echo -e "Failed:       ${RED}$FAILED_TESTS${NC}"
echo -e "Success Rate: $(echo "scale=1; $PASSED_TESTS * 100 / $TOTAL_TESTS" | bc)%"
echo ""
echo "📄 Reports generated:"
echo "  - test-report.html (main report)"
echo "  - test-report.json (detailed data)"
echo "  - plugin-test-report.json (plugin data)"
echo "  - combined-report.json (unified data)"
echo ""

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}✅ All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}❌ Some tests failed${NC}"
    exit 1
fi
