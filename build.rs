use std::env;
use std::fs;
use std::path::Path;

fn read_git_commit(dir: &Path) -> Option<String> {
    let head = dir.join(".git").join("HEAD");
    let content = fs::read_to_string(&head).ok()?;
    let line = content.lines().next()?;
    if line.starts_with("ref: ") {
        let ref_path = line.trim_start_matches("ref: ").trim();
        let ref_file = dir.join(".git").join(ref_path);
        fs::read_to_string(&ref_file)
            .ok()
            .map(|s| s.trim().to_string())
    } else {
        Some(line.to_string())
    }
}

fn main() {
    let git_commit = env::current_dir()
        .ok()
        .and_then(|cwd| read_git_commit(&cwd))
        .or_else(|| {
            env::current_dir()
                .ok()
                .and_then(|cwd| cwd.parent().and_then(|p| read_git_commit(p)))
        })
        .unwrap_or_else(|| "unknown".to_string());

    println!("cargo:rustc-env=GIT_COMMIT={}", git_commit);
}
