use clap::Parser;
use erdfa_publish::{Component, Shard, ShardSet};
use serde_json::Value;
use std::fs;
use std::path::PathBuf;
use walkdir::WalkDir;

#[derive(Parser)]
#[command(name = "freeze-chats", about = "Convert kiro-cli chat JSON to eRDFa CBOR shards")]
struct Cli {
    /// Input directory or files containing chat JSON
    inputs: Vec<PathBuf>,
    /// Output directory for CBOR shards
    #[arg(long, default_value = "shards")]
    out: PathBuf,
}

fn extract_turns(history: &[Value]) -> Vec<(String, String)> {
    let mut turns = Vec::new();
    for h in history {
        // user
        if let Some(uc) = h.get("user").and_then(|u| u.get("content")) {
            let text = if let Some(p) = uc.get("Prompt").and_then(|p| p.get("prompt")).and_then(|p| p.as_str()) {
                Some(p.to_string())
            } else if uc.is_string() {
                Some(uc.as_str().unwrap().to_string())
            } else if uc.get("ToolUseResults").is_some() {
                None
            } else {
                Some(uc.to_string())
            };
            if let Some(t) = text {
                if !t.is_empty() {
                    turns.push(("user".into(), t.chars().take(50000).collect()));
                }
            }
        }
        // assistant
        if let Some(a) = h.get("assistant") {
            let text = a.get("content").or(a.get("message")).or(a.get("Text"))
                .and_then(|v| v.as_str())
                .map(String::from)
                .or_else(|| {
                    a.get("ToolUse").and_then(|tu| tu.get("content")).and_then(|v| v.as_str()).map(String::from)
                });
            if let Some(t) = text {
                if !t.is_empty() {
                    turns.push(("assistant".into(), t.chars().take(50000).collect()));
                }
            }
        }
    }
    turns
}

fn process_chat(path: &PathBuf, out: &PathBuf) -> Option<()> {
    let data: Value = serde_json::from_str(&fs::read_to_string(path).ok()?).ok()?;
    let cid = data.get("conversation_id").and_then(|v| v.as_str()).unwrap_or("unknown");
    let history = data.get("history").and_then(|v| v.as_array())?;
    let turns = extract_turns(history);
    if turns.is_empty() { return None; }

    let summary = data.get("latest_summary").and_then(|v| v.as_str()).unwrap_or("");
    let stem = path.file_stem()?.to_string_lossy().to_string();

    let mut shards = Vec::new();

    // summary shard
    if !summary.is_empty() {
        shards.push(Shard::new(
            format!("{stem}/summary"),
            Component::Paragraph { text: summary.chars().take(5000).collect() },
        ).with_tags(vec!["chat-summary".into(), cid.into()]));
    }

    // turn shards
    for (i, (role, text)) in turns.iter().enumerate() {
        shards.push(Shard::new(
            format!("{stem}/turn-{i}"),
            Component::Code { language: role.clone(), source: text.chars().take(10000).collect() },
        ).with_tags(vec!["chat-turn".into(), role.clone(), cid.into()]));
    }

    // write shards
    let chat_dir = out.join(&stem);
    fs::create_dir_all(&chat_dir).ok()?;
    for shard in &shards {
        let fname = format!("{}.cbor", shard.id.replace('/', "_"));
        fs::write(chat_dir.join(&fname), shard.to_cbor()).ok()?;
    }

    // write manifest
    let set = ShardSet::from_shards(&stem, &shards);
    fs::write(chat_dir.join("manifest.cbor"), set.to_cbor()).ok()?;

    eprintln!("  {} → {} shards", stem, shards.len());
    Some(())
}

fn main() {
    let cli = Cli::parse();
    fs::create_dir_all(&cli.out).expect("cannot create output dir");

    let mut files: Vec<PathBuf> = Vec::new();
    for input in &cli.inputs {
        if input.is_dir() {
            for e in WalkDir::new(input).into_iter().flatten() {
                if e.path().extension().map_or(false, |x| x == "json") {
                    files.push(e.into_path());
                }
            }
        } else if input.is_file() {
            files.push(input.clone());
        }
    }
    files.sort();

    let mut count = 0;
    for f in &files {
        if process_chat(f, &cli.out).is_some() {
            count += 1;
        }
    }
    eprintln!("✅ {count} chats → eRDFa shards in {}", cli.out.display());
}
