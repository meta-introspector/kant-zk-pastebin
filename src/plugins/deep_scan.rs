// Deep Scan tile — conformal field visualization for the DASL/drisl/atproto/dag-cbor/ipld universe
// Uses data from ~/projects/dasl/IMPL/deep_scanner scan output.
use crate::plugin::{Plugin, PluginInput, PluginResult};
use std::collections::HashMap;
use std::path::Path;

pub struct DeepScanPlugin;

impl DeepScanPlugin {
    pub fn new() -> Self { Self }

    fn scan_dir() -> String {
        std::env::var("DEEP_SCAN_OUTPUT")
            .unwrap_or_else(|_| "/mnt/data1/time-2026/02-february/22/dasl/deep_scan_output".to_string())
    }

    fn load_scan_log(&self,) -> String {
        let log_path = Path::new(&Self::scan_dir()).join("scan.log");
        std::fs::read_to_string(&log_path).unwrap_or_default()
    }

    fn load_findings_car(&self,) -> Vec<u8> {
        let car_path = Path::new("/home/mdupont/projects/dasl/IMPL/deep_scanner").join("findings.car");
        std::fs::read(&car_path).unwrap_or_default()
    }

    fn load_lattice_seeds(&self,) -> String {
        let seeds_path = Path::new("/home/mdupont/projects/dasl/IMPL/deep_scanner").join("final_lattice_seeds.json");
        std::fs::read_to_string(&seeds_path).unwrap_or_else(|_| "{}".to_string())
    }

    fn extract_conformal_metrics(&self,log: &str) -> HashMap<String, serde_json::Value> {
        let mut metrics = HashMap::new();

        // Parse Hecke scores from the log
        let mut hecke_scores = Vec::new();
        let mut maass_shadows = Vec::new();

        for line in log.lines() {
            if let Some(val) = line.strip_prefix("  Hecke score: ") {
                if let Ok(v) = val.trim().parse::<f64>() {
                    hecke_scores.push(v);
                }
            }
            if let Some(val) = line.strip_prefix("  Maass shadow: ") {
                if let Ok(v) = val.trim().parse::<f64>() {
                    maass_shadows.push(v);
                }
            }
        }

        // Extract file counts
        let mut files_scanned = 0u64;
        for line in log.lines() {
            if let Some(rest) = line.strip_prefix("Scanning: ") {
                files_scanned += 1;
            }
        }

        // Extract byte frequencies
        let mut top_bytes: Vec<HashMap<String, serde_json::Value>> = Vec::new();
        for line in log.lines() {
            if let Some(rest) = line.strip_prefix("  Byte 0x") {
                let parts: Vec<&str> = rest.splitn(2, ':').collect();
                if parts.len() == 2 {
                    let byte_str = parts[0].trim();
                    let freq_str = parts[1].split(',').next().unwrap_or("0")
                        .trim().trim_start_matches("frequency = ");
                    top_bytes.push(serde_json::json!({
                        "byte": format!("0x{}", byte_str),
                        "frequency": freq_str.parse::<u64>().unwrap_or(0),
                    }));
                }
            }
            if top_bytes.len() >= 10 { break; }
        }

        // CBOR tag 42 detection
        let tag42_count = log.lines()
            .filter(|l| l.contains("Found") && l.contains("CBOR tag 42"))
            .next()
            .and_then(|l| {
                l.split_whitespace().filter_map(|w| w.parse::<u64>().ok()).next()
            })
            .unwrap_or(0);

        metrics.insert("files_scanned".to_string(), serde_json::json!(files_scanned));
        metrics.insert("hecke_scores".to_string(), serde_json::json!(hecke_scores));
        metrics.insert("maass_shadows".to_string(), serde_json::json!(maass_shadows));
        metrics.insert("top_bytes".to_string(), serde_json::json!(top_bytes));
        metrics.insert("cbor_tag42_count".to_string(), serde_json::json!(tag42_count));
        metrics.insert("avg_hecke".to_string(), serde_json::json!(
            if hecke_scores.is_empty() { 0.0 } else { hecke_scores.iter().sum::<f64>() / hecke_scores.len() as f64 }
        ));
        metrics.insert("avg_maass".to_string(), serde_json::json!(
            if maass_shadows.is_empty() { 0.0 } else { maass_shadows.iter().sum::<f64>() / maass_shadows.len() as f64 }
        ));

        metrics
    }
}

impl Plugin for DeepScanPlugin {
    fn name(&self) -> &str { "deep-scan" }
    fn version(&self) -> &str { "0.1.0" }
    fn description(&self) -> &str { "Deep Scanner — conformal field visualization of the DASL/drisl/atproto/dag-cbor/ipld universe" }

    fn execute(&self, input: &PluginInput) -> PluginResult {
        let mut map = HashMap::new();
        let action = input.extra.get("action").map(|s| s.as_str()).unwrap_or("dashboard");

        match action {
            "dashboard" | "browse" => {
                let log = self.load_scan_log();
                let metrics = self.extract_conformal_metrics(&log);
                let seeds = self.load_lattice_seeds();

                let avg_h = metrics.get("avg_hecke").and_then(|v| v.as_f64()).unwrap_or(0.0);
                let avg_m = metrics.get("avg_maass").and_then(|v| v.as_f64()).unwrap_or(0.0);
                let files = metrics.get("files_scanned").and_then(|v| v.as_u64()).unwrap_or(0);
                let tag42 = metrics.get("cbor_tag42_count").and_then(|v| v.as_u64()).unwrap_or(0);
                let monster_resonance = (avg_h * avg_m * 71.0 * 1000.0).round() / 1000.0;

                let top_bytes = metrics.get("top_bytes")
                    .and_then(|v| v.as_array())
                    .map(|arr| {
                        arr.iter().map(|b| {
                            let byte = b.get("byte").and_then(|v| v.as_str()).unwrap_or("??");
                            let freq = b.get("frequency").and_then(|v| v.as_u64()).unwrap_or(0);
                            format!("<tr><td>{}</td><td>{}</td></tr>", byte, freq)
                        }).collect::<Vec<_>>().join("\n")
                    })
                    .unwrap_or_default();

                let html = format!(
                    r#"<h1>🌀 DASL Universe Conformal Field</h1>

<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:10px;margin:10px 0">
<div class="card" style="background:#1f2937;border:1px solid #30363d;border-radius:8px;padding:15px;text-align:center">
<div style="font-size:32px">{}</div>
<div style="font-size:12px;color:#8b949e">Files Scanned</div>
</div>
<div class="card" style="background:#1f2937;border:1px solid #30363d;border-radius:8px;padding:15px;text-align:center">
<div style="font-size:32px">{:.4}</div>
<div style="font-size:12px;color:#8b949e">Avg Hecke Score</div>
</div>
<div class="card" style="background:#1f2937;border:1px solid #30363d;border-radius:8px;padding:15px;text-align:center">
<div style="font-size:32px">{:.4}</div>
<div style="font-size:12px;color:#8b949e">Avg Maass Shadow</div>
</div>
<div class="card" style="background:#1f2937;border:1px solid #30363d;border-radius:8px;padding:15px;text-align:center">
<div style="font-size:32px">{:.3}</div>
<div style="font-size:12px;color:#8b949e">Monster Resonance</div>
</div>
<div class="card" style="background:#1f2937;border:1px solid #30363d;border-radius:8px;padding:15px;text-align:center">
<div style="font-size:32px">{}</div>
<div style="font-size:12px;color:#8b949e">CBOR Tag 42 (CID)</div>
</div>
</div>

<h3>📊 Top Byte Frequencies</h3>
<table style="width:100%"><tr><th>Byte</th><th>Frequency</th></tr>{}</table>

<h3>🧬 Lattice Seeds</h3>
<pre style="max-height:300px;overflow:auto;background:#0d1117;padding:10px;border-radius:4px">{}</pre>

<h3>🔬 Scan Details</h3>
<pre style="max-height:400px;overflow:auto;background:#0d1117;padding:10px;border-radius:4px">{}</pre>

<style>
.card {{ transition: transform 0.2s; }}
.card:hover {{ transform: scale(1.05); }}
</style>"#,
                    files, avg_h, avg_m, monster_resonance, tag42,
                    top_bytes,
                    &seeds[..seeds.len().min(500)],
                    &log[..log.len().min(2000)]
                );
                map.insert("html".to_string(), html);
            }
            "scan-log" => {
                let log = self.load_scan_log();
                map.insert("content".to_string(), log);
                map.insert("content_type".to_string(), "text/plain".to_string());
            }
            "lattice" => {
                let seeds = self.load_lattice_seeds();
                map.insert("content".to_string(), seeds);
                map.insert("content_type".to_string(), "application/json".to_string());
            }
            "findings" => {
                let car = self.load_findings_car();
                map.insert("content".to_string(), format!("{:?}", car));
                map.insert("content_type".to_string(), "application/octet-stream".to_string());
                map.insert("size".to_string(), car.len().to_string());
            }
            _ => {
                map.insert("error".to_string(), format!("Unknown action: {}", action));
            }
        }
        Ok(map)
    }
}
