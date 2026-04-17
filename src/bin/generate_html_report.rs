/// Generate HTML report from test-report.json
use std::fs;

fn main() {
    let json_data = fs::read_to_string("test-report.json")
        .expect("Failed to read test-report.json");
    
    let report: serde_json::Value = serde_json::from_str(&json_data)
        .expect("Failed to parse JSON");
    
    let html = generate_html(&report);
    
    fs::write("test-report.html", html)
        .expect("Failed to write test-report.html");
    
    println!("✅ HTML report generated: test-report.html");
}

fn generate_html(report: &serde_json::Value) -> String {
    let coverage = &report["coverage"];
    let fuzz = &report["fuzz"];
    let performance = &report["performance"];
    let errors = &report["errors"];
    
    let coverage_pct = coverage["percentage"].as_u64().unwrap_or(0);
    let total = coverage["total"].as_u64().unwrap_or(0);
    let covered = coverage["covered"].as_u64().unwrap_or(0);
    
    let mut fuzz_rows = String::new();
    if let Some(fuzz_arr) = fuzz.as_array() {
        for item in fuzz_arr {
            let path = item["path"].as_str().unwrap_or("");
            let pass_rate = item["pass_rate"].as_f64().unwrap_or(0.0);
            let iterations = item["iterations"].as_u64().unwrap_or(0);
            let crashes = item["crashes"].as_u64().unwrap_or(0);
            
            let status = if pass_rate >= 99.0 { "✅" } else if pass_rate >= 95.0 { "⚠️" } else { "❌" };
            
            fuzz_rows.push_str(&format!(
                "<tr><td>{}</td><td>{}</td><td>{:.1}%</td><td>{}/{}</td></tr>\n",
                status, path, pass_rate, iterations - crashes, iterations
            ));
        }
    }
    
    let mut perf_rows = String::new();
    if let Some(perf_arr) = performance.as_array() {
        for item in perf_arr {
            let path = item["path"].as_str().unwrap_or("");
            let avg_ms = item["avg_ms"].as_f64().unwrap_or(0.0);
            let p99_ms = item["p99_ms"].as_f64().unwrap_or(0.0);
            
            let status = if avg_ms < 1.0 { "🚀" } else if avg_ms < 10.0 { "✅" } else { "⚠️" };
            
            perf_rows.push_str(&format!(
                "<tr><td>{}</td><td>{}</td><td>{:.3}ms</td><td>{:.3}ms</td></tr>\n",
                status, path, avg_ms, p99_ms
            ));
        }
    }
    
    let mut coverage_rows = String::new();
    if let Some(paths) = coverage["paths"].as_object() {
        for (path, covered) in paths {
            let status = if covered.as_bool().unwrap_or(false) { "✅" } else { "❌" };
            coverage_rows.push_str(&format!(
                "<tr><td>{}</td><td>{}</td></tr>\n",
                status, path
            ));
        }
    }
    
    let mut error_list = String::new();
    if let Some(err_arr) = errors.as_array() {
        if err_arr.is_empty() {
            error_list = "<p class='success'>✅ No errors detected</p>".to_string();
        } else {
            error_list = "<ul class='errors'>\n".to_string();
            for err in err_arr {
                if let Some(msg) = err.as_str() {
                    error_list.push_str(&format!("<li>{}</li>\n", msg));
                }
            }
            error_list.push_str("</ul>");
        }
    }
    
    let coverage_color = if coverage_pct >= 90 { "#4caf50" } else if coverage_pct >= 70 { "#ff9800" } else { "#f44336" };
    
    format!(r#"<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Kant Pastebin - Test Report</title>
    <style>
        * {{ margin: 0; padding: 0; box-sizing: border-box; }}
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #0a0a0a;
            color: #e0e0e0;
            padding: 2rem;
            line-height: 1.6;
        }}
        .container {{
            max-width: 1200px;
            margin: 0 auto;
        }}
        h1 {{
            font-size: 2.5rem;
            margin-bottom: 0.5rem;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }}
        .timestamp {{
            color: #888;
            margin-bottom: 2rem;
        }}
        .summary {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 1rem;
            margin-bottom: 2rem;
        }}
        .card {{
            background: #1a1a1a;
            border: 1px solid #333;
            border-radius: 8px;
            padding: 1.5rem;
        }}
        .card h2 {{
            font-size: 1.2rem;
            margin-bottom: 1rem;
            color: #fff;
        }}
        .metric {{
            font-size: 2.5rem;
            font-weight: bold;
            margin-bottom: 0.5rem;
        }}
        .metric-label {{
            color: #888;
            font-size: 0.9rem;
        }}
        table {{
            width: 100%;
            border-collapse: collapse;
            background: #1a1a1a;
            border: 1px solid #333;
            border-radius: 8px;
            overflow: hidden;
        }}
        th {{
            background: #2a2a2a;
            padding: 1rem;
            text-align: left;
            font-weight: 600;
            border-bottom: 2px solid #333;
        }}
        td {{
            padding: 0.75rem 1rem;
            border-bottom: 1px solid #2a2a2a;
        }}
        tr:last-child td {{
            border-bottom: none;
        }}
        tr:hover {{
            background: #222;
        }}
        .section {{
            margin-bottom: 2rem;
        }}
        .success {{
            color: #4caf50;
            font-weight: 600;
        }}
        .errors {{
            list-style: none;
            background: #2a1a1a;
            border-left: 4px solid #f44336;
            padding: 1rem 1rem 1rem 2rem;
            border-radius: 4px;
        }}
        .errors li {{
            color: #ff6b6b;
            margin-bottom: 0.5rem;
        }}
        .progress-bar {{
            width: 100%;
            height: 30px;
            background: #2a2a2a;
            border-radius: 15px;
            overflow: hidden;
            margin-top: 1rem;
        }}
        .progress-fill {{
            height: 100%;
            background: {};
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            font-weight: bold;
            transition: width 0.3s ease;
        }}
    </style>
</head>
<body>
    <div class="container">
        <h1>📊 Kant Pastebin Test Report</h1>
        <p class="timestamp">Generated: {}</p>
        
        <div class="summary">
            <div class="card">
                <h2>📦 Coverage</h2>
                <div class="metric" style="color: {}">{}/{}</div>
                <div class="metric-label">{}% code paths covered</div>
                <div class="progress-bar">
                    <div class="progress-fill" style="width: {}%; background: {}">{}%</div>
                </div>
            </div>
            
            <div class="card">
                <h2>🎲 Fuzz Testing</h2>
                <div class="metric" style="color: #4caf50">{}</div>
                <div class="metric-label">test paths fuzzed</div>
            </div>
            
            <div class="card">
                <h2>⚡ Performance</h2>
                <div class="metric" style="color: #2196f3">{}</div>
                <div class="metric-label">benchmarks executed</div>
            </div>
        </div>
        
        <div class="section">
            <div class="card">
                <h2>📋 Code Coverage</h2>
                <table>
                    <thead>
                        <tr>
                            <th>Status</th>
                            <th>Code Path</th>
                        </tr>
                    </thead>
                    <tbody>
                        {}
                    </tbody>
                </table>
            </div>
        </div>
        
        <div class="section">
            <div class="card">
                <h2>🎲 Fuzz Test Results</h2>
                <table>
                    <thead>
                        <tr>
                            <th>Status</th>
                            <th>Path</th>
                            <th>Pass Rate</th>
                            <th>Passed/Total</th>
                        </tr>
                    </thead>
                    <tbody>
                        {}
                    </tbody>
                </table>
            </div>
        </div>
        
        <div class="section">
            <div class="card">
                <h2>⚡ Performance Benchmarks</h2>
                <table>
                    <thead>
                        <tr>
                            <th>Status</th>
                            <th>Path</th>
                            <th>Average</th>
                            <th>P99</th>
                        </tr>
                    </thead>
                    <tbody>
                        {}
                    </tbody>
                </table>
            </div>
        </div>
        
        <div class="section">
            <div class="card">
                <h2>❌ Errors</h2>
                {}
            </div>
        </div>
    </div>
</body>
</html>"#,
        coverage_color,
        chrono::Utc::now().format("%Y-%m-%d %H:%M:%S UTC"),
        coverage_color,
        covered,
        total,
        coverage_pct,
        coverage_pct,
        coverage_color,
        coverage_pct,
        fuzz.as_array().map(|a| a.len()).unwrap_or(0),
        performance.as_array().map(|a| a.len()).unwrap_or(0),
        coverage_rows,
        fuzz_rows,
        perf_rows,
        error_list,
    )
}
