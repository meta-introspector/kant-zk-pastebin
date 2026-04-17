/// zkperf-based test runner - uses actual coverage data, no hardcoded numbers
use std::process::Command;
use std::fs;

fn main() {
    println!("=== zkPerf Test Runner ===\n");
    
    // Run tests with zkperf coverage
    run_with_zkperf_coverage();
    
    // Parse actual coverage data
    let coverage = parse_coverage_data();
    
    // Run plugin tests with perf recording
    let plugin_results = test_plugins_with_perf();
    
    // Generate report from real data
    generate_report(&coverage, &plugin_results);
}

fn run_with_zkperf_coverage() {
    println!("📊 Running tests with zkperf coverage...");
    
    let status = Command::new("cargo")
        .args(&["llvm-cov", "--all-features", "--workspace", "--lcov", "--output-path", "lcov.info"])
        .current_dir("../zkperf")
        .status()
        .expect("Failed to run coverage");
    
    if !status.success() {
        eprintln!("⚠️  Coverage collection failed, continuing with available data");
    }
}

fn parse_coverage_data() -> CoverageData {
    println!("📖 Parsing actual coverage data...");
    
    let lcov = fs::read_to_string("../zkperf/lcov.info")
        .or_else(|_| fs::read_to_string("lcov.info"))
        .unwrap_or_default();
    
    let mut data = CoverageData::default();
    
    for line in lcov.lines() {
        if line.starts_with("LF:") {
            if let Some(n) = line.strip_prefix("LF:").and_then(|s| s.parse().ok()) {
                data.lines_total += n;
            }
        } else if line.starts_with("LH:") {
            if let Some(n) = line.strip_prefix("LH:").and_then(|s| s.parse().ok()) {
                data.lines_hit += n;
            }
        }
    }
    
    data.percentage = if data.lines_total > 0 {
        (data.lines_hit * 100) / data.lines_total
    } else {
        0
    };
    
    println!("  Lines: {}/{} ({}%)", data.lines_hit, data.lines_total, data.percentage);
    
    data
}

fn test_plugins_with_perf() -> Vec<PluginResult> {
    println!("\n🔌 Testing plugins with perf recording...");
    
    let plugins = vec!["html5ever", "cssparser", "oxc"];
    let mut results = Vec::new();
    
    for plugin in plugins {
        println!("  Testing {}...", plugin);
        
        let perf_data = format!("plugin_{}.perf.data", plugin);
        
        // Record actual perf data
        let status = Command::new("perf")
            .args(&["record", "-o", &perf_data, "--", 
                    "cargo", "test", "--package", plugin])
            .status();
        
        let mut result = PluginResult {
            name: plugin.to_string(),
            cycles: 0,
            instructions: 0,
            cache_misses: 0,
        };
        
        if status.is_ok() && status.unwrap().success() {
            // Parse perf data
            if let Ok(output) = Command::new("perf")
                .args(&["report", "-i", &perf_data, "--stdio"])
                .output() 
            {
                let report = String::from_utf8_lossy(&output.stdout);
                result.cycles = extract_metric(&report, "cycles");
                result.instructions = extract_metric(&report, "instructions");
                result.cache_misses = extract_metric(&report, "cache-misses");
            }
        }
        
        results.push(result);
    }
    
    results
}

fn extract_metric(report: &str, metric: &str) -> u64 {
    report.lines()
        .find(|l| l.contains(metric))
        .and_then(|l| l.split_whitespace().next())
        .and_then(|s| s.replace(",", "").parse().ok())
        .unwrap_or(0)
}

fn generate_report(coverage: &CoverageData, plugins: &[PluginResult]) {
    println!("\n📄 Generating report from actual data...");
    
    let report = serde_json::json!({
        "timestamp": chrono::Utc::now().to_rfc3339(),
        "coverage": {
            "lines_total": coverage.lines_total,
            "lines_hit": coverage.lines_hit,
            "percentage": coverage.percentage,
            "source": "llvm-cov"
        },
        "plugins": plugins.iter().map(|p| {
            serde_json::json!({
                "name": p.name,
                "cycles": p.cycles,
                "instructions": p.instructions,
                "cache_misses": p.cache_misses,
                "source": "perf record"
            })
        }).collect::<Vec<_>>()
    });
    
    fs::write("zkperf-test-report.json", serde_json::to_string_pretty(&report).unwrap())
        .expect("Failed to write report");
    
    println!("✅ Report saved: zkperf-test-report.json");
    println!("\nActual Results:");
    println!("  Coverage: {}%", coverage.percentage);
    println!("  Plugins tested: {}", plugins.len());
}

#[derive(Default)]
struct CoverageData {
    lines_total: u64,
    lines_hit: u64,
    percentage: u64,
}

struct PluginResult {
    name: String,
    cycles: u64,
    instructions: u64,
    cache_misses: u64,
}
