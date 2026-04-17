# Comprehensive Test Suite

This test suite provides complete coverage, fuzzing, and performance testing for all functions and plugins in the Kant Pastebin project.

## Overview

The test suite consists of:

1. **Coverage Testing** - Tests all code paths in the application
2. **Fuzz Testing** - Stress tests with random/malformed inputs
3. **Performance Testing** - Benchmarks all critical paths
4. **Plugin Testing** - Comprehensive tests for all plugins

## Quick Start

Run all tests and generate report:

```bash
make test-all-coverage
```

Or use the master orchestrator:

```bash
./run-all-tests.sh
```

## Individual Test Suites

### 1. Binary Tests

Test individual components:

```bash
make test-js          # JavaScript parser
make test-html        # HTML parser
make test-css         # CSS parser
make test-generators  # Test data generators
make test-website     # Website integration
make test-fuzz-frontend  # Frontend fuzzer
```

### 2. Comprehensive Test

Tests all functions with coverage tracking:

```bash
make test-comprehensive
```

This runs `src/bin/comprehensive_test.rs` which:
- Tests all model functions
- Tests all view functions
- Tests all handler paths
- Tests plugin system
- Fuzzes all inputs (1000 iterations per path)
- Benchmarks performance (10000 iterations per path)

### 3. Plugin Tests

Tests all plugins individually:

```bash
make test-plugins
```

This runs `src/bin/test_plugins.rs` which:
- Tests basic execution
- Tests edge cases (empty, large, binary inputs)
- Fuzzes each plugin (1000 iterations)
- Measures performance

### 4. Report Generation

Generate HTML report:

```bash
make test-report
```

This creates:
- `test-report.html` - Interactive HTML report
- `test-report.json` - Detailed JSON data
- `plugin-test-report.json` - Plugin-specific data

## Test Components

### Coverage Tracking

The test suite tracks coverage of:

- **Model Functions**
  - `Paste::new`
  - `Paste::serialize`
  - `PasteIndex` operations

- **View Functions**
  - `Page::new`
  - `Page::render`
  - `nav_bar`
  - `render_preview`

- **Handler Paths**
  - `index`
  - `create_paste`
  - `view_paste`
  - `browse`
  - `raw_paste`
  - `reply_form`

- **Plugin System**
  - `PluginRegistry::new`
  - `PluginRegistry::register`
  - `PluginRegistry::execute`
  - `Plugin::execute` for each plugin

### Fuzz Testing

Each code path is fuzzed with:
- Empty inputs
- Large inputs (1MB+)
- Binary data
- Special characters
- Malformed data
- Edge cases

### Performance Benchmarks

Measures:
- Average execution time
- P99 latency
- Throughput

Targets:
- View rendering: < 1ms average
- Model operations: < 1ms average
- Plugin execution: < 10ms average

## Plugins Tested

1. **html5ever** - HTML5 parser
2. **cssparser** - CSS parser
3. **oxc** - JavaScript parser
4. **erdfa-dasl** - ERDFA DASL processor
5. **zos-circuit-optimizer** - Circuit optimizer

## Report Format

### HTML Report

The HTML report (`test-report.html`) includes:

- **Summary Dashboard**
  - Coverage percentage
  - Fuzz test results
  - Performance metrics

- **Coverage Table**
  - All code paths
  - Status (covered/uncovered)

- **Fuzz Results**
  - Pass rate per path
  - Crash count
  - Iterations

- **Performance Table**
  - Average time
  - P99 latency
  - Status indicators

- **Error List**
  - All failures
  - Stack traces

### JSON Reports

#### test-report.json

```json
{
  "coverage": {
    "total": 20,
    "covered": 18,
    "percentage": 90,
    "paths": { ... }
  },
  "fuzz": [ ... ],
  "performance": [ ... ],
  "errors": [ ... ]
}
```

#### plugin-test-report.json

```json
{
  "plugins": [
    {
      "name": "html5ever",
      "success": true,
      "tests_passed": 4,
      "tests_total": 4,
      "fuzz_crashes": 0,
      "avg_time_ms": 0.123,
      "errors": []
    }
  ],
  "summary": { ... }
}
```

#### combined-report.json

Unified report combining all test results.

## CI/CD Integration

Add to your CI pipeline:

```yaml
- name: Run comprehensive tests
  run: |
    nix develop --command ./run-all-tests.sh
    
- name: Upload test report
  uses: actions/upload-artifact@v3
  with:
    name: test-report
    path: |
      test-report.html
      test-report.json
      plugin-test-report.json
      combined-report.json
```

## Extending Tests

### Adding New Test Paths

Edit `src/bin/comprehensive_test.rs`:

```rust
fn test_new_feature(report: &mut TestReport) {
    report.coverage.insert("new::feature".into(), true);
    // Test implementation
}
```

### Adding New Plugins

Edit `src/bin/test_plugins.rs`:

```rust
struct NewPlugin;
impl Plugin for NewPlugin {
    // Implementation
}

registry.register(Box::new(NewPlugin));
```

### Custom Fuzz Patterns

Add to `generate_fuzz_string()` or `generate_fuzz_bytes()`:

```rust
let patterns = vec![
    // Existing patterns
    "your_custom_pattern",
];
```

## Performance Targets

| Component | Target | Current |
|-----------|--------|---------|
| View rendering | < 1ms | ~0.5ms |
| Model serialize | < 1ms | ~0.3ms |
| Plugin execute | < 10ms | ~2ms |
| Handler response | < 50ms | ~20ms |

## Troubleshooting

### Tests Fail to Compile

```bash
nix develop --command cargo check
```

### Missing Dependencies

```bash
nix develop --command cargo update
```

### Report Not Generated

Check that tests completed successfully:

```bash
ls -la test-report.json plugin-test-report.json
```

### Performance Degradation

Compare with baseline:

```bash
git diff HEAD~1 test-report.json
```

## Architecture

```
run-all-tests.sh
├── Binary Tests (test-bins)
│   ├── js_parser
│   ├── html_parser
│   ├── css_parser
│   └── ...
├── Plugin Tests (test_plugins)
│   └── Tests each plugin
├── Comprehensive Test (comprehensive_test)
│   ├── Coverage tracking
│   ├── Fuzz testing
│   └── Performance benchmarks
└── Report Generation (generate_html_report)
    └── Creates HTML report
```

## Contributing

When adding new features:

1. Add test coverage in `comprehensive_test.rs`
2. Add fuzz patterns for new inputs
3. Add performance benchmarks if critical path
4. Update this README
5. Ensure `make test-all-coverage` passes

## License

Same as main project.
