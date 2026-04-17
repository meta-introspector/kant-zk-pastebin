# zkPerf-Based Testing

**Primary Method:** zkPerf witness system  
**Comparison:** Standard tools (llvm-cov, perf stat)

## Quick Start

```bash
./test-with-zkperf.sh
```

## What It Does

### 1. zkPerf Witness Testing (Primary)
- Records each component with `perf record --call-graph dwarf`
- Extracts witness data with `perf script`
- Generates verifiable `.perf.data` files
- **Showcases zkPerf's witness system**

### 2. Standard Tools (Comparison)
- Runs `llvm-cov` for line coverage
- Runs `perf stat` for basic metrics
- Shows zkPerf advantages

## Output

```
zkperf-test-report.json
test-recordings/
├── js_parser.perf.data       # zkPerf witness
├── js_parser.witness.txt     # Extracted witness
├── html_parser.perf.data
├── css_parser.perf.data
└── ...
```

## Report Format

```json
{
  "primary_method": "zkperf",
  "zkperf_witnesses": [
    {
      "component": "js_parser",
      "samples": 12345,
      "perf_data": "test-recordings/js_parser.perf.data",
      "witness": "test-recordings/js_parser.witness.txt",
      "method": "zkperf perf record + witness extraction"
    }
  ],
  "comparison_tools": {
    "llvm_cov": { "lines_hit": 1234, "lines_total": 5678 },
    "perf_stat": { "report": "..." }
  }
}
```

## Why zkPerf

✅ **Witness-based verification** - Not just coverage numbers
✅ **Call graph recording** - Full execution trace
✅ **Perf data artifacts** - Verifiable evidence
✅ **No mocked data** - Real recordings
✅ **Reproducible** - Can replay witnesses

## Comparison Shows

- zkPerf provides **verifiable witnesses**
- Standard tools provide **aggregate metrics**
- zkPerf enables **proof of execution**
