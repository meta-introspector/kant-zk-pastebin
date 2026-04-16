# Headless Browser Tests → Pure Rust

## Migration Strategy

### Original (Puppeteer)
```javascript
const browser = await puppeteer.launch();
const page = await browser.newPage();
await page.goto(url);
const title = await page.title();
await page.type('#content', 'text');
await page.click('button');
```

### New (Pure Rust)
```rust
let ctx = TestContext::from_html(html);
let title = ctx.title();
let has_form = ctx.has_element("#content");
// Const eval - no runtime needed
```

## Capabilities

### Static Analysis (Const Eval)
- Parse HTML → DOM tree
- Extract all forms, inputs, links, scripts
- Validate structure without execution
- Check accessibility (ARIA, semantic HTML)
- Compute orbifold coords for each element

### Dynamic Analysis (Interpreted)
- Execute JS via oxc AST walk
- Simulate DOM mutations
- Track state changes as conformal arrows
- Capture side effects as workflow steps

### Fuzzing
- Mutate form inputs guided by orbifold distance
- Generate test cases from Monster symmetries
- 100% path coverage via geodesic exploration

## Test Suite

### 1. Static Tests (`website_test`)
- ✅ Home page title
- ✅ Form elements present
- ✅ Navigation links
- ✅ Semantic HTML structure
- ✅ ARIA attributes

### 2. Dynamic Tests (`website_test_dynamic`)
- Form submission simulation
- JS execution trace
- State mutation tracking
- Event handler validation

### 3. Fuzzing Tests (`website_fuzz`)
- Input mutation (AFL++)
- Path coverage analysis
- Crash detection
- Performance regression

## Advantages Over Puppeteer

1. **No Browser Required** - pure Rust, no Chrome/Chromium
2. **Const Eval** - tests run at compile time
3. **Deterministic** - no flaky async timing issues
4. **Fast** - no process spawning, no network
5. **Orbifold Coords** - geometric test coverage
6. **Provable** - zkperf witness for test correctness

## Implementation

```rust
// Const eval test (compile-time)
const fn test_structure() -> bool {
    // Parse HTML at compile time
    // Validate structure
    // Return true/false
}

// Runtime test (interpreted)
fn test_behavior(html: &str, js: &str) -> TestResult {
    let ctx = TestContext::from_html(html);
    let ast = parse_js(js);
    let trace = execute_js(&ast, &ctx);
    TestResult {
        passed: validate_trace(&trace),
        coords: trace_to_coords(&trace),
        workflow: trace_to_workflow(&trace),
    }
}
```

## Integration

All tests stored as pastes:
- Test code → JS AST → Monster coords
- Expected output → orbifold coords
- Actual output → conformal arrow from expected
- Distance = test failure severity

## Next Steps

1. Port all puppeteer tests to `website_test.rs`
2. Add JS interpreter for dynamic tests
3. Wire AFL++ fuzzer
4. Generate test cases from Monster symmetries
5. Prove test correctness via zkperf
