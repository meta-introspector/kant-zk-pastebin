use std::env;
use std::fs;
use std::path::Path;

fn main() {
    // Embed git commit from .git/HEAD without shell-out
    let git_commit = if let Ok(cwd) = env::current_dir() {
        let head = cwd.join(".git").join("HEAD");
        if let Ok(content) = fs::read_to_string(&head) {
            let line = content.lines().next().unwrap_or("");
            if line.starts_with("ref: ") {
                let ref_path = line.trim_start_matches("ref: ").trim();
                let ref_file = cwd.join(".git").join(ref_path);
                fs::read_to_string(&ref_file)
                    .ok()
                    .map(|s| s.trim().to_string())
                    .unwrap_or_else(|| line.to_string())
            } else {
                line.to_string()
            }
        } else {
            "unknown".to_string()
        }
    } else {
        "unknown".to_string()
    };

    println!("cargo:rustc-env=GIT_COMMIT={}", git_commit);
}
