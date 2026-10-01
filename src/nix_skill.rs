// Nix Skill — analyzes flake.nix files and exposes structured info
// Focus: flake.nix parsing, input/output extraction, dependency graphing

use regex_lite::Regex;
use std::collections::HashMap;
use std::fs;

/// Structured representation of a flake.nix analysis
#[derive(serde::Serialize, serde::Deserialize, Clone, Debug)]
pub struct FlakeAnalysis {
    pub path: String,
    pub description: Option<String>,
    pub inputs: Vec<FlakeInput>,
    pub packages: Vec<String>,
    pub dev_shells: Vec<String>,
    pub apps: Vec<String>,
    pub system_configs: Vec<String>,
    pub nixpkgs_url: Option<String>,
    pub has_tests: bool,
    pub has_checks: bool,
    pub has_formatter: bool,
    pub warnings: Vec<String>,
}

#[derive(serde::Serialize, serde::Deserialize, Clone, Debug)]
pub struct FlakeInput {
    pub name: String,
    pub url: Option<String>,
    pub follows: Vec<String>,
    pub is_flake: bool,
    pub is_path: bool,
    pub is_git: bool,
}

/// Analyze a flake.nix file at the given path
pub fn analyze_flake(path: &str) -> Result<FlakeAnalysis, String> {
    let content = fs::read_to_string(path).map_err(|e| format!("Cannot read {}: {}", path, e))?;

    let content_trimmed = content.trim();

    // Check it's actually a flake.nix
    if !content_trimmed.starts_with('{') || !content_contains(&content, "inputs") {
        return Err("Not a valid flake.nix (missing 'inputs' attribute)".to_string());
    }

    let mut analysis = FlakeAnalysis {
        path: path.to_string(),
        description: None,
        inputs: Vec::new(),
        packages: Vec::new(),
        dev_shells: Vec::new(),
        apps: Vec::new(),
        system_configs: Vec::new(),
        nixpkgs_url: None,
        has_tests: false,
        has_checks: false,
        has_formatter: false,
        warnings: Vec::new(),
    };

    // Extract description
    let desc_re = Regex::new(r#"description\s*=\s*"([^"]*)"#).unwrap();
    if let Some(cap) = desc_re.captures(&content) {
        analysis.description = Some(cap[1].to_string());
    }

    // Extract inputs
    let input_re = Regex::new(r"(?m)^\s+([a-zA-Z0-9_-]+)\s*=\s*\{").unwrap();
    for cap in input_re.captures_iter(&content) {
        let name = cap[1].to_string();
        if name == "self" || name.starts_with("//") {
            continue;
        }

        let mut input = FlakeInput {
            name: name.clone(),
            url: None,
            follows: Vec::new(),
            is_flake: true,
            is_path: false,
            is_git: false,
        };

        // Find this input's block content
        if let Some(block) = extract_block(&content, &name) {
            // Check url
            let url_re = Regex::new(r#"\burl\s*=\s*"([^"]+)""#).unwrap();
            if let Some(u) = url_re.captures(&block) {
                let url_str = u[1].to_string();
                input.url = Some(url_str.clone());
                input.is_path = url_str.starts_with("path:");
                input.is_git = url_str.contains("git+");
            }

            // Check follows
            let follows_re = Regex::new(r#"\bfollows\s*=\s*"([^"]+)""#).unwrap();
            for f in follows_re.captures_iter(&block) {
                input.follows.push(f[1].to_string());
            }

            // Check flake = false
            if block.contains("flake = false") || block.contains("flake=false") {
                input.is_flake = false;
            }

            // Track nixpkgs URL
            if name == "nixpkgs" {
                analysis.nixpkgs_url = input.url.clone();
            }
        }

        analysis.inputs.push(input);
    }

    // Extract packages from outputs
    let pkg_re = Regex::new(r"(?m)^\s+(\w+)\s*=\s*(pkgs\.[a-zA-Z.]+|self\.packages|nixpkgs\.legacyPackages|pkgs\.callPackage|pkgs\.buildRustPackage|pkgs\.stdenv\.mkDerivation|pkgs\.writeShellScriptBin|pkgs\.rustPlatform\.buildRustPackage)").unwrap();
    for cap in pkg_re.captures_iter(&content) {
        let pkg_name = cap[1].to_string();
        if !analysis.packages.contains(&pkg_name) && pkg_name != "packages" && pkg_name != "default"
        {
            analysis.packages.push(pkg_name);
        }
    }

    // Extract packages from `packages = { ... }` blocks
    let pkgs_block_re = Regex::new(r"(?ms)packages\s*=\s*\{([^}]+)\}").unwrap();
    for cap in pkgs_block_re.captures_iter(&content) {
        let block = &cap[1];
        let inner_re = Regex::new(r"(?m)^\s+(\w+(?:-\w+)*)\s*=").unwrap();
        for inner in inner_re.captures_iter(block) {
            let name = inner[1].to_string();
            if !analysis.packages.contains(&name) && name != "inherit" {
                analysis.packages.push(name);
            }
        }
    }

    // Detect devShells
    if content.contains("devShells") || content_contains(&content, "mkShell") {
        let shell_re = Regex::new(r"(?m)^\s+(\w+(?:-\w+)*)\s*=\s*pkgs\.mkShell").unwrap();
        for cap in shell_re.captures_iter(&content) {
            analysis.dev_shells.push(cap[1].to_string());
        }
        if analysis.dev_shells.is_empty() {
            analysis.dev_shells.push("default".to_string());
        }
    }

    // Detect apps
    if content.contains("apps") {
        let app_re = Regex::new(r"(?m)^\s+(\w+(?:-\w+)*)\s*=\s*\{").unwrap();
        // Only look inside the apps block
        if let Some(block) = extract_block_by_key(&content, "apps") {
            for cap in app_re.captures_iter(&block) {
                let name = cap[1].to_string();
                if name != "type" && name != "program" && !analysis.apps.contains(&name) {
                    analysis.apps.push(name);
                }
            }
        }
    }

    // Detect systemConfigs
    if content.contains("systemConfigs") {
        let sc_re =
            Regex::new(r"(?m)^\s+(\w+(?:-\w+)*)\s*=\s*system-manager\.lib\.makeSystemConfig")
                .unwrap();
        for cap in sc_re.captures_iter(&content) {
            analysis.system_configs.push(cap[1].to_string());
        }
    }

    // Feature detection
    analysis.has_tests = content_contains(&content, "doCheck") || content.contains("checkPhase");
    analysis.has_checks = content_contains_bool(&content, "checks");
    analysis.has_formatter = content_contains(&content, "formatter")
        || content.contains("treefmt")
        || content.contains("nixpkgs-fmt");

    // Warnings
    if let Some(nixpkgs_url) = &analysis.nixpkgs_url {
        if !nixpkgs_url.contains("file://") {
            analysis.warnings.push(format!(
                "nixpkgs URL points to remote: {} — consider mirroring locally for purity",
                nixpkgs_url
            ));
        } else {
            analysis
                .warnings
                .push("nixpkgs uses local mirror — ✓".to_string());
        }
    }

    // Check for cargoLock vs cargoVendorDir (purity)
    if content.contains("cargoLock") {
        analysis
            .warnings
            .push("Uses cargoLock.lockFile — build will fetch from crates.io (impure)".to_string());
    } else if content.contains("cargoVendorDir") {
        analysis
            .warnings
            .push("Uses cargoVendorDir — pure local build ✓".to_string());
    }

    // Check for flake.lock
    let flake_lock = format!(
        "{}/flake.lock",
        fs::canonicalize(path)
            .map(|p| p
                .parent()
                .map(|pp| pp.to_string_lossy().to_string())
                .unwrap_or_default())
            .unwrap_or_default()
    );
    if fs::metadata(&flake_lock).is_err() {
        analysis
            .warnings
            .push("No flake.lock found — dependencies may drift".to_string());
    }

    Ok(analysis)
}

/// Analyze multiple flake.nix files and return a summary
pub fn analyze_flakes(paths: &[String]) -> Vec<FlakeAnalysis> {
    let mut results = Vec::new();
    for path in paths {
        match analyze_flake(path) {
            Ok(a) => results.push(a),
            Err(e) => {
                results.push(FlakeAnalysis {
                    path: path.clone(),
                    description: Some(format!("ERROR: {}", e)),
                    inputs: vec![],
                    packages: vec![],
                    dev_shells: vec![],
                    apps: vec![],
                    system_configs: vec![],
                    nixpkgs_url: None,
                    has_tests: false,
                    has_checks: false,
                    has_formatter: false,
                    warnings: vec![],
                });
            }
        }
    }
    results
}

// ─── Helpers ─────────────────────────────────────────────────────────────

fn content_contains(content: &str, pattern: &str) -> bool {
    content.contains(pattern)
}

fn content_contains_bool(content: &str, attr: &str) -> bool {
    let re = Regex::new(&format!(r"(?m)^\s+{}\s*=\s*true", regex_lite::escape(attr))).unwrap();
    re.is_match(content)
}

/// Extract the block content for a named input attribute
fn extract_block(content: &str, name: &str) -> Option<String> {
    // Find the line: name = {
    let re = Regex::new(&format!(r"(?m)^{}\s*=\s*\{{", regex_lite::escape(name))).unwrap();
    let start = re.find(content)?;
    let start_byte = start.start();
    let mut depth = 0;
    let mut started = false;
    let mut end_byte = start_byte;

    for (i, ch) in content[start_byte..].char_indices() {
        match ch {
            '{' => {
                depth += 1;
                started = true;
            }
            '}' => {
                depth -= 1;
                if started && depth == 0 {
                    end_byte = start_byte + i + ch.len_utf8();
                    break;
                }
            }
            _ => {}
        }
    }

    if depth != 0 {
        return None;
    }
    Some(content[start_byte..end_byte].to_string())
}

/// Extract the block content for a top-level key like `apps` or `packages`
fn extract_block_by_key(content: &str, key: &str) -> Option<String> {
    let re = Regex::new(&format!(r"(?m)^\s+{}\s*=\s*\{{", regex_lite::escape(key))).unwrap();
    let start = re.find(content)?;
    let start_byte = start.start();
    let mut depth = 0;
    let mut started = false;
    let mut end_byte = start_byte;

    for (i, ch) in content[start_byte..].char_indices() {
        match ch {
            '{' => {
                depth += 1;
                started = true;
            }
            '}' => {
                depth -= 1;
                if started && depth == 0 {
                    end_byte = start_byte + i + ch.len_utf8();
                    break;
                }
            }
            _ => {}
        }
    }

    if depth != 0 {
        return None;
    }
    Some(content[start_byte..end_byte].to_string())
}
