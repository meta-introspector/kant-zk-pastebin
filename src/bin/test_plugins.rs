/// Plugin-specific comprehensive test suite
use kant_pastebin::plugin::{Plugin, PluginInput, PluginRegistry};
use std::collections::HashMap;

fn main() {
    println!("=== Plugin Comprehensive Test Suite ===\n");
    
    let mut registry = PluginRegistry::new();
    
    // Register all available plugins
    register_all_plugins(&mut registry);
    
    // Test each plugin
    let plugins = registry.list();
    println!("📦 Found {} plugins\n", plugins.len());
    
    let mut results = Vec::new();
    
    for (name, version, description) in plugins {
        println!("Testing plugin: {} v{}", name, version);
        println!("  Description: {}", description);
        
        let result = test_plugin(&registry, name);
        results.push((name.to_string(), result));
        
        println!();
    }
    
    // Generate report
    generate_plugin_report(&results);
    
    let failed = results.iter().filter(|(_, r)| !r.success).count();
    std::process::exit(if failed == 0 { 0 } else { 1 });
}

struct PluginTestResult {
    success: bool,
    tests_passed: usize,
    tests_total: usize,
    fuzz_crashes: usize,
    avg_time_ms: f64,
    errors: Vec<String>,
}

fn register_all_plugins(registry: &mut PluginRegistry) {
    // Mock plugins for testing
    struct HtmlPlugin;
    impl Plugin for HtmlPlugin {
        fn name(&self) -> &str { "html5ever" }
        fn version(&self) -> &str { "0.1.0" }
        fn description(&self) -> &str { "HTML5 parser" }
        fn execute(&self, input: &PluginInput) -> Result<HashMap<String, String>, String> {
            let content = String::from_utf8_lossy(&input.content);
            let mut result = HashMap::new();
            result.insert("parsed".into(), "true".into());
            result.insert("length".into(), content.len().to_string());
            Ok(result)
        }
    }
    
    struct CssPlugin;
    impl Plugin for CssPlugin {
        fn name(&self) -> &str { "cssparser" }
        fn version(&self) -> &str { "0.1.0" }
        fn description(&self) -> &str { "CSS parser" }
        fn execute(&self, input: &PluginInput) -> Result<HashMap<String, String>, String> {
            let content = String::from_utf8_lossy(&input.content);
            let mut result = HashMap::new();
            result.insert("rules".into(), "0".into());
            Ok(result)
        }
    }
    
    struct JsPlugin;
    impl Plugin for JsPlugin {
        fn name(&self) -> &str { "oxc" }
        fn version(&self) -> &str { "0.1.0" }
        fn description(&self) -> &str { "JavaScript parser" }
        fn execute(&self, input: &PluginInput) -> Result<HashMap<String, String>, String> {
            let content = String::from_utf8_lossy(&input.content);
            let mut result = HashMap::new();
            result.insert("ast_nodes".into(), "0".into());
            Ok(result)
        }
    }
    
    struct ErdfaPlugin;
    impl Plugin for ErdfaPlugin {
        fn name(&self) -> &str { "erdfa-dasl" }
        fn version(&self) -> &str { "0.1.0" }
        fn description(&self) -> &str { "ERDFA DASL processor" }
        fn execute(&self, input: &PluginInput) -> Result<HashMap<String, String>, String> {
            let mut result = HashMap::new();
            result.insert("triples".into(), "0".into());
            Ok(result)
        }
    }
    
    struct CircuitPlugin;
    impl Plugin for CircuitPlugin {
        fn name(&self) -> &str { "zos-circuit-optimizer" }
        fn version(&self) -> &str { "0.1.0" }
        fn description(&self) -> &str { "ZOS circuit optimizer" }
        fn execute(&self, input: &PluginInput) -> Result<HashMap<String, String>, String> {
            let mut result = HashMap::new();
            result.insert("optimized".into(), "true".into());
            Ok(result)
        }
    }
    
    registry.register(Box::new(HtmlPlugin));
    registry.register(Box::new(CssPlugin));
    registry.register(Box::new(JsPlugin));
    registry.register(Box::new(ErdfaPlugin));
    registry.register(Box::new(CircuitPlugin));
}

fn test_plugin(registry: &PluginRegistry, name: &str) -> PluginTestResult {
    let mut result = PluginTestResult {
        success: true,
        tests_passed: 0,
        tests_total: 0,
        fuzz_crashes: 0,
        avg_time_ms: 0.0,
        errors: Vec::new(),
    };
    
    // Test 1: Basic execution
    result.tests_total += 1;
    let input = PluginInput {
        id: "test_001".into(),
        content: b"test content".to_vec(),
        mime: "text/plain".into(),
        url: "http://test".into(),
        extra: HashMap::new(),
    };
    
    match registry.execute(name, &input) {
        Ok(_) => {
            result.tests_passed += 1;
            println!("  ✅ Basic execution");
        }
        Err(e) => {
            result.success = false;
            result.errors.push(format!("Basic execution failed: {}", e));
            println!("  ❌ Basic execution: {}", e);
        }
    }
    
    // Test 2: Empty input
    result.tests_total += 1;
    let empty_input = PluginInput {
        id: "test_002".into(),
        content: vec![],
        mime: "text/plain".into(),
        url: "http://test".into(),
        extra: HashMap::new(),
    };
    
    match registry.execute(name, &empty_input) {
        Ok(_) => {
            result.tests_passed += 1;
            println!("  ✅ Empty input");
        }
        Err(e) => {
            result.errors.push(format!("Empty input failed: {}", e));
            println!("  ⚠️  Empty input: {}", e);
        }
    }
    
    // Test 3: Large input
    result.tests_total += 1;
    let large_input = PluginInput {
        id: "test_003".into(),
        content: vec![b'x'; 1_000_000],
        mime: "text/plain".into(),
        url: "http://test".into(),
        extra: HashMap::new(),
    };
    
    match registry.execute(name, &large_input) {
        Ok(_) => {
            result.tests_passed += 1;
            println!("  ✅ Large input (1MB)");
        }
        Err(e) => {
            result.errors.push(format!("Large input failed: {}", e));
            println!("  ⚠️  Large input: {}", e);
        }
    }
    
    // Test 4: Binary input
    result.tests_total += 1;
    let binary_input = PluginInput {
        id: "test_004".into(),
        content: (0..=255).collect(),
        mime: "application/octet-stream".into(),
        url: "http://test".into(),
        extra: HashMap::new(),
    };
    
    match registry.execute(name, &binary_input) {
        Ok(_) => {
            result.tests_passed += 1;
            println!("  ✅ Binary input");
        }
        Err(e) => {
            result.errors.push(format!("Binary input failed: {}", e));
            println!("  ⚠️  Binary input: {}", e);
        }
    }
    
    // Fuzz test
    println!("  🎲 Fuzzing (1000 iterations)...");
    let fuzz_iterations = 1000;
    let mut times = Vec::new();
    
    for i in 0..fuzz_iterations {
        let fuzz_input = PluginInput {
            id: format!("fuzz_{}", i),
            content: generate_fuzz_input(i),
            mime: "application/octet-stream".into(),
            url: "http://test".into(),
            extra: HashMap::new(),
        };
        
        let start = std::time::Instant::now();
        let exec_result = std::panic::catch_unwind(|| {
            registry.execute(name, &fuzz_input)
        });
        times.push(start.elapsed().as_micros() as f64 / 1000.0);
        
        if exec_result.is_err() {
            result.fuzz_crashes += 1;
        }
    }
    
    result.avg_time_ms = times.iter().sum::<f64>() / times.len() as f64;
    
    let pass_rate = ((fuzz_iterations - result.fuzz_crashes) as f64 / fuzz_iterations as f64) * 100.0;
    println!("  🎲 Fuzz: {:.1}% pass rate, avg {:.3}ms", pass_rate, result.avg_time_ms);
    
    if result.fuzz_crashes > 0 {
        result.success = false;
        result.errors.push(format!("{} crashes during fuzzing", result.fuzz_crashes));
    }
    
    result
}

fn generate_fuzz_input(seed: usize) -> Vec<u8> {
    let patterns: Vec<Vec<u8>> = vec![
        vec![],
        vec![0],
        vec![255],
        b"<html></html>".to_vec(),
        b"body { color: red; }".to_vec(),
        b"function test() {}".to_vec(),
        vec![0; 10000],
        (0..=255).cycle().take(1000).collect(),
        b"\xFF\xFE\x00\x00".to_vec(),
        b"<?xml version=\"1.0\"?>".to_vec(),
    ];
    patterns[seed % patterns.len()].clone()
}

fn generate_plugin_report(results: &[(String, PluginTestResult)]) {
    println!("\n=== Plugin Test Report ===\n");
    
    let mut total_tests = 0;
    let mut total_passed = 0;
    let mut total_crashes = 0;
    
    for (name, result) in results {
        total_tests += result.tests_total;
        total_passed += result.tests_passed;
        total_crashes += result.fuzz_crashes;
        
        let status = if result.success { "✅" } else { "❌" };
        println!("{} {} - {}/{} tests, {} crashes, {:.3}ms avg",
            status, name, result.tests_passed, result.tests_total,
            result.fuzz_crashes, result.avg_time_ms);
        
        if !result.errors.is_empty() {
            for error in &result.errors {
                println!("     ⚠️  {}", error);
            }
        }
    }
    
    println!("\n📊 Summary:");
    println!("  Total tests: {}", total_tests);
    println!("  Passed: {}", total_passed);
    println!("  Failed: {}", total_tests - total_passed);
    println!("  Fuzz crashes: {}", total_crashes);
    
    // Save JSON report
    let json = serde_json::json!({
        "plugins": results.iter().map(|(name, result)| {
            serde_json::json!({
                "name": name,
                "success": result.success,
                "tests_passed": result.tests_passed,
                "tests_total": result.tests_total,
                "fuzz_crashes": result.fuzz_crashes,
                "avg_time_ms": result.avg_time_ms,
                "errors": result.errors,
            })
        }).collect::<Vec<_>>(),
        "summary": {
            "total_tests": total_tests,
            "total_passed": total_passed,
            "total_crashes": total_crashes,
        }
    });
    
    std::fs::write("plugin-test-report.json", serde_json::to_string_pretty(&json).unwrap())
        .expect("Failed to write plugin report");
    
    println!("\n📄 Report saved to plugin-test-report.json");
}
