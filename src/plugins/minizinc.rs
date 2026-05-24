// MiniZinc tile — constraint solving with MiniZinc, for optimization problems
use crate::plugin::{Plugin, PluginInput, PluginResult};
use std::collections::HashMap;
use std::process::Command;

pub struct MiniZincPlugin;

impl MiniZincPlugin {
    pub fn new() -> Self { Self }

    fn solve(&self, model: &str, solver: &str, timeout: u64) -> Result<String, String> {
        let tmp_dir = std::env::temp_dir();
        let mzn_file = tmp_dir.join("model.mzn");
        std::fs::write(&mzn_file, model).map_err(|e| format!("write model: {}", e))?;

        let output = Command::new("minizinc")
            .args([
                "--solver", solver,
                "--time-limit", &format!("{}", timeout * 1000),
                mzn_file.to_str().unwrap(),
            ])
            .output()
            .map_err(|e| format!("minizinc not found: {}", e))?;

        if output.status.success() {
            Ok(String::from_utf8_lossy(&output.stdout).to_string())
        } else {
            Err(format!("minizinc error: {}", String::from_utf8_lossy(&output.stderr)))
        }
    }

    fn find_solvers(&self) -> Vec<String> {
        let output = Command::new("minizinc")
            .args(["--solvers"])
            .output().ok()
            .and_then(|o| String::from_utf8(o.stdout).ok())
            .unwrap_or_default();
        output.lines()
            .filter(|l| l.contains("Gecode") || l.contains("Chuffed") || l.contains("HiGHS"))
            .map(|l| {
                l.split_whitespace().next().unwrap_or(l).to_string()
            })
            .collect()
    }
}

impl Plugin for MiniZincPlugin {
    fn name(&self) -> &str { "minizinc" }
    fn version(&self) -> &str { "0.1.0" }
    fn description(&self) -> &str { "MiniZinc constraint solver tile — model, solve, and visualize optimization problems" }

    fn execute(&self, input: &PluginInput) -> PluginResult {
        let mut map = HashMap::new();
        let action = input.extra.get("action").map(|s| s.as_str()).unwrap_or("solve");
        let content = std::str::from_utf8(&input.content).unwrap_or("");

        match action {
            "solve" => {
                let solver = input.extra.get("solver").map(|s| s.as_str()).unwrap_or("gecode");
                let timeout = input.extra.get("timeout").and_then(|t| t.parse().ok()).unwrap_or(30);
                match self.solve(content, solver, timeout) {
                    Ok(solution) => {
                        map.insert("solution".to_string(), solution);
                        map.insert("solver".to_string(), solver.to_string());
                    }
                    Err(e) => { map.insert("error".to_string(), e); }
                }
            }
            "solvers" => {
                let solvers = self.find_solvers();
                map.insert("solvers".to_string(), solvers.join(", "));
                map.insert("count".to_string(), solvers.len().to_string());
            }
            "browse" => {
                let files = locate_files("mzn", 100);
                let html = files.iter().map(|(name, path)| {
                    format!(r#"<li><a href="?action=view&path={}">{}</a></li>"#, path, name)
                }).collect::<Vec<_>>().join("\n");
                map.insert("html".to_string(), format!(
                    "<h1>🧮 MiniZinc Models</h1>
<p>Submit a model in the textarea below, or browse existing files.</p>
<form><textarea name='model' rows='10' cols='80' placeholder='int: x; constraint x > 5; solve satisfy;'></textarea>
<br>solver: <select name='solver'><option>gecode</option><option>chuffed</option></select>
<button>Solve</button></form><ul>{}</ul>", html));
            }
            _ => {
                map.insert("error".to_string(), format!("Unknown action: {}", action));
            }
        }
        Ok(map)
    }
}

fn locate_files(ext: &str, max: usize) -> Vec<(String, String)> {
    let output = std::process::Command::new("locate")
        .args(["-r", &format!("\\.{}$", ext)])
        .output().ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .unwrap_or_default();
    output.lines()
        .filter(|l| !l.is_empty())
        .take(max)
        .map(|l| {
            let name = std::path::Path::new(l).file_name()
                .map(|n| n.to_string_lossy().to_string())
                .unwrap_or_else(|| l.to_string());
            (name, l.to_string())
        })
        .collect()
}
