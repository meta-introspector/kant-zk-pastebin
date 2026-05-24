// Lean4 tile — theorem proving with Lean 4, verify statements and browse proofs
use crate::plugin::{Plugin, PluginInput, PluginResult};
use std::collections::HashMap;
use std::process::Command;

pub struct LeanPlugin;

impl LeanPlugin {
    pub fn new() -> Self { Self }

    fn verify(&self, code: &str) -> Result<String, String> {
        let tmp_dir = std::env::temp_dir();
        let lean_file = tmp_dir.join("verify.lean");
        std::fs::write(&lean_file, code).map_err(|e| format!("write: {}", e))?;

        let output = Command::new("lean")
            .args([lean_file.to_str().unwrap()])
            .output()
            .map_err(|e| format!("lean not found: {}", e))?;

        if output.status.success() {
            Ok(String::from_utf8_lossy(&output.stdout).to_string())
        } else {
            let stderr = String::from_utf8_lossy(&output.stderr);
            // Extract error info
            if stderr.contains("error") {
                Err(format!("❌ Proof failed:\n{}", stderr))
            } else {
                Ok(stderr.to_string())
            }
        }
    }

    fn check_syntax(&self, code: &str) -> Result<String, String> {
        let tmp_dir = std::env::temp_dir();
        let lean_file = tmp_dir.join("syntax.lean");
        std::fs::write(&lean_file, code).map_err(|e| format!("write: {}", e))?;

        let output = Command::new("lean")
            .args(["--syntax", lean_file.to_str().unwrap()])
            .output()
            .map_err(|e| format!("lean: {}", e))?;

        if output.status.success() {
            Ok("✅ Syntax OK".to_string())
        } else {
            Err(format!("❌ Syntax error:\n{}", String::from_utf8_lossy(&output.stderr)))
        }
    }
}

impl Plugin for LeanPlugin {
    fn name(&self) -> &str { "lean" }
    fn version(&self) -> &str { "0.1.0" }
    fn description(&self) -> &str { "Lean 4 theorem prover tile — verify mathematical proofs, check syntax, browse libraries" }

    fn execute(&self, input: &PluginInput) -> PluginResult {
        let mut map = HashMap::new();
        let action = input.extra.get("action").map(|s| s.as_str()).unwrap_or("verify");
        let content = std::str::from_utf8(&input.content).unwrap_or("");

        match action {
            "verify" => {
                match self.verify(content) {
                    Ok(out) => {
                        map.insert("result".to_string(), "verified".to_string());
                        map.insert("output".to_string(), out);
                    }
                    Err(e) => {
                        map.insert("result".to_string(), "failed".to_string());
                        map.insert("error".to_string(), e);
                    }
                }
            }
            "syntax" => {
                match self.check_syntax(content) {
                    Ok(msg) => { map.insert("result".to_string(), msg); }
                    Err(e) => { map.insert("error".to_string(), e); }
                }
            }
            "browse" => {
                let files = locate_files("lean", 100);
                let html = files.iter().map(|(name, path)| {
                    format!(r#"<li><a href="?action=view&path={}">{}</a></li>"#, path, name)
                }).collect::<Vec<_>>().join("\n");
                map.insert("html".to_string(), format!(
                    "<h1>🏛️ Lean 4 Proofs</h1>
<p>Enter a Lean 4 theorem to verify:</p>
<form><textarea name='code' rows='10' cols='80' placeholder='theorem add_comm (a b : Nat) : a + b = b + a := by
  induction a with
  | zero => simp
  | succ a ih => simp [add_succ, ih]'></textarea>
<br><button>Verify</button> <button onclick='this.form.action.value=\"syntax\"'>Check Syntax</button></form>
<h3>Existing files:</h3><ul>{}</ul>", html));
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
