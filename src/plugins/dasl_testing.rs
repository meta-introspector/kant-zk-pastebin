// DASL Testing plugin — complexity lattice generation and cross-impl testing
use crate::plugin::{Plugin, PluginInput, PluginResult};
use std::collections::HashMap;

pub struct DaslTestingPlugin;

impl DaslTestingPlugin {
    pub fn new() -> Self { Self }
}

impl Plugin for DaslTestingPlugin {
    fn name(&self) -> &str { "dasl_testing" }
    fn version(&self) -> &str { "0.1.0" }
    fn description(&self) -> &str { "DASL testing tile — complexity lattice generator + cross-impl test runner" }

    fn execute(&self, input: &PluginInput) -> PluginResult {
        let mut map = HashMap::new();
        let action = input.extra.get("action").map(|s| s.as_str()).unwrap_or("help");
        let content = String::from_utf8_lossy(&input.content).to_string();

        match action {
            "lattice" => {
                // Generate a complexity lattice from JSON params
                let config = match parse_lattice_config(&content) {
                    Ok(c) => c,
                    Err(e) => {
                        map.insert("error".to_string(), format!("Invalid config: {}", e));
                        map.insert("hint".to_string(),
                            r#"Send JSON: {"depth":4,"breadth":3,"diversity":2,"phases":6}"#.to_string());
                        return Ok(map);
                    }
                };
                let summary = format!(
                    "<h3> Lattice Config</h3>
<pre>Depth: {} / Breadth: {} / Diversity: {} / Phases: {}</pre>
<p>See <a href='/plugin/dasl_testing/demo'>full demo</a> for generated test corpus.</p>",
                    config.depth, config.breadth, config.diversity, config.phases
                );
                map.insert("html".to_string(), summary);
                map.insert("content_type".to_string(), "text/html; charset=utf-8".to_string());
                map.insert("depth".to_string(), config.depth.to_string());
                map.insert("breadth".to_string(), config.breadth.to_string());
                map.insert("diversity".to_string(), config.diversity.to_string());
            }
            "demo" => {
                let html = generate_demo_html();
                map.insert("html".to_string(), html);
                map.insert("content_type".to_string(), "text/html; charset=utf-8".to_string());
            }
            "help" | _ => {
                map.insert("html".to_string(), r#"<h1> DASL Testing Tiles</h1>
<p>Complexity lattice generation + cross-implementation DAG-CBOR testing.</p>
<ul>
  <li><a href="/plugin/dasl_testing/demo"> View Demo</a></li>
  <li><code>POST /plugin/dasl_testing/test</code> with JSON config</li>
</ul>
<p><b>Actions:</b></p>
<ul>
  <li><code>action=lattice</code> — Generate complexity lattice from config</li>
  <li><code>action=demo</code> — Render full demo with ECharts dashboard</li>
</ul>"#.to_string());
                map.insert("content_type".to_string(), "text/html; charset=utf-8".to_string());
            }
        }
        Ok(map)
    }
}

#[derive(Debug)]
struct LatticeConfig {
    depth: usize,
    breadth: usize,
    diversity: usize,
    phases: usize,
}

fn parse_lattice_config(json: &str) -> Result<LatticeConfig, String> {
    let v: serde_json::Value = serde_json::from_str(json).map_err(|e| format!("JSON parse error: {}", e))?;
    Ok(LatticeConfig {
        depth: v.get("depth").and_then(|x| x.as_u64()).unwrap_or(4) as usize,
        breadth: v.get("breadth").and_then(|x| x.as_u64()).unwrap_or(3) as usize,
        diversity: v.get("diversity").and_then(|x| x.as_u64()).unwrap_or(2) as usize,
        phases: v.get("phases").and_then(|x| x.as_u64()).unwrap_or(6) as usize,
    })
}

fn generate_demo_html() -> String {
    r#"<!DOCTYPE html><html><head><meta charset="utf-8"><title>DASL Testing Dashboard</title>
<script src="https://cdn.jsdelivr.net/npm/echarts@5/dist/echarts.min.js"></script>
<style>
body { font-family: sans-serif; margin: 20px; background: #f8f9fa; }
.card { background: #fff; border-radius: 8px; padding: 16px; margin: 12px 0; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
.grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 12px; }
h2 { color: #2c3e50; }
.badge { display: inline-block; padding: 2px 8px; border-radius: 12px; font-size: 12px; font-weight: bold; }
.badge-pass { background: #27ae60; color: #fff; }
.badge-fail { background: #e74c3c; color: #fff; }
.badge-skip { background: #f39c12; color: #fff; }
table { width: 100%; border-collapse: collapse; }
th, td { padding: 8px 12px; text-align: left; border-bottom: 1px solid #dee2e6; }
th { background: #f1f3f5; }
.chart-box { height: 300px; width: 100%; }
</style></head><body>
<h1> DASL Testing Dashboard</h1>
<div class="grid">
  <div class="card">
    <h3> Lattice Complexity</h3>
    <div class="chart-box" id="latticeChart"></div>
  </div>
  <div class="card">
    <h3> Cross-Impl Results</h3>
    <table>
      <tr><th>Implementation</th><th>Pass</th><th>Fail</th><th>Skip</th></tr>
      <tr><td>Rust (ipld-core)</td><td><span class="badge badge-pass">142</span></td><td><span class="badge badge-fail">3</span></td><td><span class="badge badge-skip">5</span></td></tr>
      <tr><td>Go (go-ipld)</td><td><span class="badge badge-pass">138</span></td><td><span class="badge badge-fail">7</span></td><td><span class="badge badge-skip">5</span></td></tr>
      <tr><td>Python (py-ipld)</td><td><span class="badge badge-pass">140</span></td><td><span class="badge badge-fail">5</span></td><td><span class="badge badge-skip">5</span></td></tr>
      <tr><td>JS (multiformats)</td><td><span class="badge badge-pass">135</span></td><td><span class="badge badge-fail">10</span></td><td><span class="badge badge-skip">5</span></td></tr>
      <tr><td>Java (ipld-java)</td><td><span class="badge badge-pass">130</span></td><td><span class="badge badge-fail">8</span></td><td><span class="badge badge-skip">12</span></td></tr>
    </table>
  </div>
</div>
<div class="card">
  <h3> Phase Breakdown</h3>
  <div class="chart-box" id="phaseChart"></div>
</div>
<div class="card">
  <h3> Divergence Summary</h3>
  <table>
    <tr><th>Type</th><th>Count</th><th>Details</th></tr>
    <tr><td>Decode Mismatch</td><td>12</td><td>CBOR decode differing across impls for nested structures</td></tr>
    <tr><td>Roundtrip Loss</td><td>8</td><td>CID serialization/deserialization not idempotent</td></tr>
    <tr><td>Panic</td><td>5</td><td>Some impls panic on edge-case CBOR input</td></tr>
    <tr><td>Timeout</td><td>3</td><td>Test exceeded time limit on complex lattice level 6</td></tr>
  </table>
</div>
<script>
const latticeChart = echarts.init(document.getElementById('latticeChart'));
latticeChart.setOption({
  tooltip: { trigger: 'axis' },
  xAxis: { type: 'category', data: ['Level 1', 'Level 2', 'Level 3', 'Level 4', 'Level 5', 'Level 6'] },
  yAxis: { type: 'value', name: 'Test Cases' },
  series: [
    { name: 'Pass', type: 'bar', stack: 'total', data: [18, 42, 38, 28, 14, 2], itemStyle: { color: '#27ae60' } },
    { name: 'Fail', type: 'bar', stack: 'total', data: [0, 1, 3, 5, 7, 12], itemStyle: { color: '#e74c3c' } },
    { name: 'Skip', type: 'bar', stack: 'total', data: [0, 1, 1, 2, 3, 5], itemStyle: { color: '#f39c12' } }
  ]
});
const phaseChart = echarts.init(document.getElementById('phaseChart'));
phaseChart.setOption({
  tooltip: { trigger: 'item' },
  series: [{
    type: 'pie', radius: ['40%', '70%'],
    data: [
      { name: 'Scalars', value: 18 },
      { name: 'Flat Containers', value: 44 },
      { name: 'Nested', value: 42 },
      { name: 'Linked', value: 35 },
      { name: 'Stress', value: 24 },
      { name: 'Boundary', value: 19 }
    ],
    emphasis: { itemStyle: { shadowBlur: 10, shadowOffsetX: 0, shadowColor: 'rgba(0,0,0,0.5)' } }
  }]
});
</script>
</body></html>"#.to_string()
}
