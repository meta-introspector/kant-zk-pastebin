use std::{collections::HashMap, env, fs, path::PathBuf, process};
use kant_pastebin::model::PasteIndex;
use kant_pastebin::tagging::slugify;
use sha2::{Sha256, Digest};
use erdfa_publish::{Shard, Component, cft};

const SPOOL: &str = "/mnt/data1/spool/uucp/pastebin";
const SHARD_SPOOL: &str = "/mnt/data1/spool/dasl/pastebin";
const PASTE_API: &str = "http://127.0.0.1:8090/pastebin";
const RMQ_API: &str = "http://localhost:15672/api";
const RMQ_AUTH: (&str, &str) = ("monster", "gyroscope");
const RMQ_VHOST: &str = "%2Fmonster";

fn parse_paste(path: &PathBuf) -> Option<PasteIndex> {
    let text = fs::read_to_string(path).ok()?;
    let fname = path.file_name()?.to_str()?;
    let id = fname.trim_end_matches(".txt");

    let mut title = String::new();
    let mut keywords = Vec::new();
    let mut cid = String::new();
    let mut witness = String::new();
    let mut reply_to = None;
    let mut ipfs_cid = None;
    let mut dasl = None;
    let mut body_lines = Vec::new();
    let mut in_body = false;

    for line in text.lines() {
        if in_body {
            body_lines.push(line);
            continue;
        }
        if line.starts_with("Title: ") {
            title = line[7..].to_string();
        } else if line.starts_with("Keywords: ") {
            keywords = line[10..].split(',').map(|s| s.trim().to_string()).filter(|s| !s.is_empty()).collect();
        } else if line.starts_with("CID: ") {
            cid = line[5..].to_string();
        } else if line.starts_with("Witness: ") {
            witness = line[9..].to_string();
        } else if line.starts_with("IPFS: ") {
            ipfs_cid = Some(line[6..].to_string());
        } else if line.starts_with("DASL: ") {
            dasl = Some(line[6..].to_string());
        } else if line.starts_with("Reply-To: ") {
            let rt = line[10..].trim();
            if !rt.is_empty() { reply_to = Some(rt.to_string()); }
        } else if line.is_empty() && !title.is_empty() {
            in_body = true;
        }
    }

    // Extract timestamp from id (first 15 chars: YYYYMMDD_HHMMSS)
    let timestamp = if id.len() >= 15 { id[..15].to_string() } else { String::new() };

    Some(PasteIndex {
        id: id.to_string(),
        title,
        description: dasl,
        keywords,
        cid,
        witness,
        timestamp,
        filename: fname.to_string(),
        ngrams: vec![],
        ipfs_cid,
        reply_to,
        size: body_lines.join("\n").len(),
        uucp_path: path.to_string_lossy().to_string(),
    })
}

fn load_all() -> Vec<PasteIndex> {
    let spool = env::var("UUCP_SPOOL").unwrap_or_else(|_| SPOOL.to_string());
    let mut pastes: Vec<PasteIndex> = fs::read_dir(&spool)
        .unwrap_or_else(|e| { eprintln!("Cannot read {}: {}", spool, e); process::exit(1); })
        .filter_map(|e| e.ok())
        .filter(|e| e.path().extension().map(|x| x == "txt").unwrap_or(false))
        .filter_map(|e| parse_paste(&e.path()))
        .collect();
    pastes.sort_by(|a, b| b.timestamp.cmp(&a.timestamp));
    pastes
}

fn cmd_list(n: usize) {
    let pastes = load_all();
    for p in pastes.iter().take(n) {
        let rt = p.reply_to.as_deref().unwrap_or("");
        let rt_mark = if rt.is_empty() { "" } else { " ↩" };
        println!("{} | {:40} | {:20} | {}B{}", &p.timestamp, p.title, p.keywords.join(","), p.size, rt_mark);
    }
    eprintln!("({} total pastes)", pastes.len());
}

fn cmd_thread(id: &str) {
    let pastes = load_all();
    let by_id: HashMap<&str, &PasteIndex> = pastes.iter().map(|p| (p.id.as_str(), p)).collect();

    // Find root of thread
    let mut root_id = id;
    while let Some(p) = by_id.get(root_id) {
        if let Some(ref rt) = p.reply_to {
            if by_id.contains_key(rt.as_str()) {
                root_id = rt.as_str();
                continue;
            }
        }
        break;
    }

    // Collect children
    let mut children: HashMap<&str, Vec<&str>> = HashMap::new();
    for p in &pastes {
        if let Some(ref rt) = p.reply_to {
            children.entry(rt.as_str()).or_default().push(p.id.as_str());
        }
    }

    // Print tree
    fn print_tree(id: &str, by_id: &HashMap<&str, &PasteIndex>, children: &HashMap<&str, Vec<&str>>, depth: usize) {
        let indent = "  ".repeat(depth);
        if let Some(p) = by_id.get(id) {
            println!("{}├─ {} | {}", indent, &p.id, p.title);
        }
        if let Some(kids) = children.get(id) {
            for kid in kids {
                print_tree(kid, by_id, children, depth + 1);
            }
        }
    }

    print_tree(root_id, &by_id, &children, 0);
}

fn cmd_post(title: &str, content: &str, reply_to: Option<&str>, keywords: &[String]) {
    let api = env::var("PASTE_API").unwrap_or_else(|_| PASTE_API.to_string());
    let url = format!("{}/paste", api).replace("/pastebin/paste", "/paste");

    let body = serde_json::json!({
        "content": content,
        "title": title,
        "keywords": keywords,
        "reply_to": reply_to,
    });

    let client = reqwest::blocking::Client::new();
    match client.post(&url).json(&body).send() {
        Ok(resp) if resp.status().is_success() => {
            let text = resp.text().unwrap_or_default();
            if let Ok(r) = serde_json::from_str::<serde_json::Value>(&text) {
                let id = r["id"].as_str().unwrap_or("?");
                let cid = r["cid"].as_str().unwrap_or("?");
                let uucp = r["uucp_path"].as_str().unwrap_or("?");
                println!("{}", id);
                eprintln!("CID: {}", cid);
                eprintln!("UUCP: {}", uucp);
                if let Some(ipfs) = r["ipfs_cid"].as_str() {
                    eprintln!("IPFS: {}", ipfs);
                }
            } else {
                print!("{}", text);
            }
        }
        Ok(resp) => { eprintln!("API error: {}", resp.status()); process::exit(1); }
        Err(e) => { eprintln!("Request failed: {} — falling back to spool", e); cmd_post_spool(title, content, reply_to, keywords); }
    }
}

fn cmd_post_spool(title: &str, content: &str, reply_to: Option<&str>, keywords: &[String]) {
    let ts = chrono::Utc::now().format("%Y%m%d_%H%M%S").to_string();
    let slug = slugify(title);
    let id = format!("{}_{}", ts, slug);

    let mut hasher = Sha256::new();
    hasher.update(content.as_bytes());
    let hash = hasher.finalize();
    let cid = format!("bafk{}", hex::encode(&hash[..16]));
    let witness = hex::encode(&hash);

    let spool = env::var("UUCP_SPOOL").unwrap_or_else(|_| SPOOL.to_string());
    let path = format!("{}/{}.txt", spool, id);

    let out = format!("--- {} ---\nTitle: {}\nKeywords: {}\nCID: {}\nWitness: {}\nReply-To: {}\n\n{}",
        id, title, keywords.join(", "), cid, witness,
        reply_to.unwrap_or(""), content);

    fs::write(&path, &out).unwrap_or_else(|e| { eprintln!("Write failed: {}", e); process::exit(1); });
    println!("{}", id);
    eprintln!("Wrote {}", path);
}

fn cmd_route(id: &str, exchange: &str, routing_key: &str) {
    let pastes = load_all();
    let paste = pastes.iter().find(|p| p.id == id || p.id.contains(id));
    let paste = match paste {
        Some(p) => p,
        None => { eprintln!("Paste not found: {}", id); process::exit(1); }
    };

    let payload = serde_json::to_string(&paste).unwrap();
    let body = serde_json::json!({
        "properties": {"content_type": "application/json"},
        "routing_key": routing_key,
        "payload": payload,
        "payload_encoding": "string"
    });

    let url = format!("{}/exchanges/{}/{}/publish", RMQ_API, RMQ_VHOST, exchange);
    let client = reqwest::blocking::Client::new();
    let resp = client.post(&url)
        .basic_auth(RMQ_AUTH.0, Some(RMQ_AUTH.1))
        .json(&body)
        .send();

    match resp {
        Ok(r) if r.status().is_success() => println!("Routed {} → {}:{}", id, exchange, routing_key),
        Ok(r) => eprintln!("RMQ error: {}", r.status()),
        Err(e) => eprintln!("Request failed: {}", e),
    }
}

fn cmd_delete(id: &str) {
    let spool = env::var("UUCP_SPOOL").unwrap_or_else(|_| SPOOL.to_string());
    let trash = format!("{}/.trash", spool);
    fs::create_dir_all(&trash).ok();

    let pastes = load_all();
    let paste = pastes.iter().find(|p| p.id == id || p.id.contains(id));
    match paste {
        Some(p) => {
            let dest = format!("{}/{}", trash, p.filename);
            fs::rename(&p.uucp_path, &dest).unwrap_or_else(|e| {
                eprintln!("Failed: {}", e); process::exit(1);
            });
            println!("Deleted {} → .trash/", p.id);
        }
        None => { eprintln!("Not found: {}", id); process::exit(1); }
    }
}

fn cmd_restore(id: &str) {
    let spool = env::var("UUCP_SPOOL").unwrap_or_else(|_| SPOOL.to_string());
    let trash = format!("{}/.trash", spool);

    let entries: Vec<_> = fs::read_dir(&trash)
        .unwrap_or_else(|_| { eprintln!("No .trash dir"); process::exit(1); })
        .filter_map(|e| e.ok())
        .filter(|e| {
            let name = e.file_name().to_string_lossy().to_string();
            name.contains(id) && name.ends_with(".txt")
        })
        .collect();

    if entries.is_empty() {
        eprintln!("Not found in trash: {}", id); process::exit(1);
    }
    for e in entries {
        let dest = format!("{}/{}", spool, e.file_name().to_string_lossy());
        fs::rename(e.path(), &dest).unwrap_or_else(|er| {
            eprintln!("Failed: {}", er); process::exit(1);
        });
        println!("Restored {}", e.file_name().to_string_lossy());
    }
}

fn cmd_trash_list() {
    let spool = env::var("UUCP_SPOOL").unwrap_or_else(|_| SPOOL.to_string());
    let trash = format!("{}/.trash", spool);
    let mut entries: Vec<_> = fs::read_dir(&trash)
        .unwrap_or_else(|_| { eprintln!("No .trash dir"); process::exit(1); })
        .filter_map(|e| e.ok())
        .filter(|e| e.path().extension().map(|x| x == "txt").unwrap_or(false))
        .collect();
    entries.sort_by_key(|e| e.file_name());
    for e in &entries {
        let name = e.file_name().to_string_lossy().to_string();
        let size = e.metadata().map(|m| m.len()).unwrap_or(0);
        println!("  {} | {}B", name.trim_end_matches(".txt"), size);
    }
    eprintln!("({} in trash)", entries.len());
}

fn cmd_show(id: &str) {
    let pastes = load_all();
    let paste = pastes.iter().find(|p| p.id == id || p.id.contains(id));
    match paste {
        Some(p) => {
            let content = fs::read_to_string(&p.uucp_path).unwrap_or_default();
            print!("{}", content);
        }
        None => { eprintln!("Not found: {}", id); process::exit(1); }
    }
}

fn read_body(path: &str) -> String {
    let content = fs::read_to_string(path).unwrap_or_default();
    let mut in_body = false;
    let mut lines = Vec::new();
    for line in content.lines() {
        if in_body { lines.push(line); }
        else if line.is_empty() { in_body = true; }
    }
    lines.join("\n")
}

fn cmd_export(id: &str, thread: bool, format: &str) {
    let pastes = load_all();
    let ids: Vec<&PasteIndex> = if thread {
        // Collect thread: root + all replies
        let by_id: HashMap<&str, &PasteIndex> = pastes.iter().map(|p| (p.id.as_str(), p)).collect();
        let mut root = id;
        while let Some(p) = by_id.get(root) {
            if let Some(ref rt) = p.reply_to { if by_id.contains_key(rt.as_str()) { root = rt; continue; } }
            break;
        }
        pastes.iter().filter(|p| p.id == root || p.reply_to.as_deref() == Some(root)).collect()
    } else {
        pastes.iter().filter(|p| p.id == id || p.id.contains(id)).take(1).collect()
    };
    if ids.is_empty() { eprintln!("Not found: {}", id); process::exit(1); }

    match format {
        "json" => {
            let items: Vec<serde_json::Value> = ids.iter().map(|p| {
                serde_json::json!({ "id": p.id, "title": p.title, "keywords": p.keywords,
                    "cid": p.cid, "reply_to": p.reply_to, "body": read_body(&p.uucp_path) })
            }).collect();
            println!("{}", serde_json::to_string_pretty(&items).unwrap());
        }
        "html" => {
            // Self-contained HTML with erdfa skin
            let css = r#"*{box-sizing:border-box;margin:0;padding:0}body{font:16px/1.6 system-ui,sans-serif;max-width:960px;margin:2rem auto;padding:0 1rem;background:#0d1117;color:#c9d1d9}a{color:#58a6ff}h1,h2,h3{margin:1rem 0 .5rem;color:#f0f6fc}pre{background:#161b22;padding:1rem;overflow-x:auto;border-radius:6px;margin:1rem 0}code{font-family:'Fira Code',monospace;font-size:14px}.shard-card{border:1px solid #30363d;border-radius:8px;padding:1rem;margin:1rem 0}.tag{display:inline-block;background:#1f6feb33;color:#58a6ff;padding:2px 8px;border-radius:12px;font-size:12px;margin:2px}dl{display:grid;grid-template-columns:auto 1fr;gap:.3rem 1rem;margin:1rem 0}dt{font-weight:600;color:#8b949e}"#;
            let title = if thread { format!("Thread: {}", ids[0].title) } else { ids[0].title.clone() };
            let mut cards = String::new();
            for p in &ids {
                let body = read_body(&p.uucp_path);
                let tags: String = p.keywords.iter().map(|t| format!("<span class=\"tag\">{}</span>", t)).collect();
                let body_hex = hex::encode(body.as_bytes());
                cards.push_str(&format!(
                    "<article class=\"shard-card\"><h2>{title}</h2><p><code>{id}</code></p>\
                     <div>{tags}</div><pre><code>{body}</code></pre>\
                     <script type=\"application/cbor+hex\" id=\"shard-{id}\">{hex}</script></article>",
                    title = p.title, id = p.id, tags = tags, body = body, hex = body_hex
                ));
            }
            println!("<!DOCTYPE html><html lang=\"en\"><head><meta charset=\"utf-8\">\
                <meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">\
                <title>{}</title><style>{}</style></head><body><h1>{}</h1>{}</body></html>",
                title, css, title, cards);
        }
        _ => { eprintln!("Unknown format: {} (use html, json)", format); process::exit(1); }
    }
}

fn cmd_import(path: &str, reply_to: Option<&str>) {
    let content = fs::read_to_string(path).unwrap_or_else(|e| { eprintln!("Cannot read {}: {}", path, e); process::exit(1); });

    if path.ends_with(".html") || path.ends_with(".htm") {
        // Extract CBOR hex from <script type="application/cbor+hex"> tags
        let mut count = 0;
        for chunk in content.split("<script type=\"application/cbor+hex\"") {
            if count == 0 { count += 1; continue; } // skip before first match
            if let Some(end) = chunk.find("</script>") {
                let hex_start = chunk.find('>').unwrap_or(0) + 1;
                let hex_data = &chunk[hex_start..end];
                if let Ok(bytes) = hex::decode(hex_data.trim()) {
                    let body = String::from_utf8_lossy(&bytes);
                    // Extract title from preceding <h2> if possible
                    let title = format!("imported-shard-{}", count);
                    cmd_post(&title, &body, reply_to, &["imported".to_string(), "erdfa".to_string()]);
                    count += 1;
                }
            }
        }
        if count <= 1 { eprintln!("No CBOR shards found in HTML"); process::exit(1); }
        eprintln!("Imported {} shards", count - 1);
    } else {
        // Plain text import
        let title = std::path::Path::new(path).file_stem()
            .map(|s| s.to_string_lossy().to_string()).unwrap_or_else(|| "imported".into());
        cmd_post(&title, &content, reply_to, &["imported".to_string()]);
    }
}

fn cmd_replies(id: &str) {
    let api = env::var("PASTE_API").unwrap_or_else(|_| PASTE_API.to_string());
    let url = format!("{}/thread/{}", api, id);
    match reqwest::blocking::get(&url) {
        Ok(resp) if resp.status().is_success() => {
            let text = resp.text().unwrap_or_default();
            if let Ok(v) = serde_json::from_str::<serde_json::Value>(&text) {
                let count = v["count"].as_u64().unwrap_or(0);
                eprintln!("Thread {} — {} posts", id, count);
                if let Some(posts) = v["posts"].as_array() {
                    for p in posts {
                        let pid = p["id"].as_str().unwrap_or("?");
                        let title = p["title"].as_str().unwrap_or("");
                        let rt = p["reply_to"].as_str().unwrap_or("");
                        let body = p["content"].as_str().unwrap_or("");
                        let preview: String = body.chars().take(80).collect();
                        let marker = if rt.is_empty() { "●" } else { "  ↩" };
                        println!("{} {} | {} | {}", marker, pid, title, preview.replace('\n', " "));
                    }
                }
            } else {
                print!("{}", text);
            }
        }
        _ => {
            // Fallback to local thread
            eprintln!("API unavailable, using local spool");
            cmd_thread(id);
        }
    }
}

fn cmd_tags(tag: Option<&str>) {
    let pastes = load_all();
    if let Some(tag) = tag {
        let tag_lower = tag.to_lowercase();
        let matches: Vec<&PasteIndex> = pastes.iter()
            .filter(|p| p.keywords.iter().any(|k| k.to_lowercase().contains(&tag_lower)))
            .collect();
        eprintln!("{} pastes tagged '{}'", matches.len(), tag);
        for p in &matches {
            println!("{} | {:40} | {}", &p.timestamp, p.title, p.keywords.join(","));
        }
    } else {
        // Show all tags with counts
        let mut tag_counts: HashMap<String, usize> = HashMap::new();
        for p in &pastes {
            for k in &p.keywords {
                let k = k.to_lowercase();
                if !k.is_empty() { *tag_counts.entry(k).or_default() += 1; }
            }
        }
        let mut tags: Vec<(String, usize)> = tag_counts.into_iter().collect();
        tags.sort_by(|a, b| b.1.cmp(&a.1));
        for (tag, count) in tags.iter().take(50) {
            println!("{:4} {}", count, tag);
        }
        eprintln!("({} unique tags)", tags.len());
    }
}

fn cmd_search(query: &str) {
    let pastes = load_all();
    let q = query.to_lowercase();
    let matches: Vec<&PasteIndex> = pastes.iter()
        .filter(|p| {
            p.title.to_lowercase().contains(&q)
            || p.keywords.iter().any(|k| k.to_lowercase().contains(&q))
            || p.id.to_lowercase().contains(&q)
        })
        .collect();
    eprintln!("{} matches for '{}'", matches.len(), query);
    for p in &matches {
        let rt = if p.reply_to.is_some() { " ↩" } else { "" };
        println!("{} | {:40} | {:20} | {}B{}", &p.timestamp, p.title, p.keywords.join(","), p.size, rt);
    }
}

fn cmd_garden() {
    let pastes = load_all();

    // Threads: find all roots and count depth
    let by_id: HashMap<&str, &PasteIndex> = pastes.iter().map(|p| (p.id.as_str(), p)).collect();
    let mut children: HashMap<&str, Vec<&str>> = HashMap::new();
    let mut has_parent = std::collections::HashSet::new();
    for p in &pastes {
        if let Some(ref rt) = p.reply_to {
            children.entry(rt.as_str()).or_default().push(p.id.as_str());
            has_parent.insert(p.id.as_str());
        }
    }
    let roots: Vec<&str> = children.keys()
        .filter(|id| !has_parent.contains(**id))
        .copied().collect();

    fn thread_size(id: &str, children: &HashMap<&str, Vec<&str>>) -> usize {
        1 + children.get(id).map(|kids| kids.iter().map(|k| thread_size(k, children)).sum::<usize>()).unwrap_or(0)
    }

    let mut threads: Vec<(&str, usize)> = roots.iter()
        .map(|r| (*r, thread_size(r, &children)))
        .filter(|(_, s)| *s > 1)
        .collect();
    threads.sort_by(|a, b| b.1.cmp(&a.1));

    // Tag cloud
    let mut tag_counts: HashMap<String, usize> = HashMap::new();
    for p in &pastes {
        for k in &p.keywords {
            let k = k.to_lowercase();
            if !k.is_empty() { *tag_counts.entry(k).or_default() += 1; }
        }
    }
    let mut tags: Vec<(String, usize)> = tag_counts.into_iter().collect();
    tags.sort_by(|a, b| b.1.cmp(&a.1));

    // Orphans (no thread, no tags, no IPFS)
    let orphans: Vec<&PasteIndex> = pastes.iter()
        .filter(|p| p.reply_to.is_none() && p.keywords.is_empty() && p.ipfs_cid.is_none() && !children.contains_key(p.id.as_str()))
        .collect();

    // Stats
    let with_ipfs = pastes.iter().filter(|p| p.ipfs_cid.is_some()).count();
    let with_tags = pastes.iter().filter(|p| !p.keywords.is_empty()).count();
    let in_threads = has_parent.len() + roots.len();

    println!("=== GARDEN REPORT ===");
    println!("Total pastes:  {}", pastes.len());
    println!("With IPFS CID: {}", with_ipfs);
    println!("With tags:     {}", with_tags);
    println!("In threads:    {}", in_threads);
    println!("Orphans:       {}", orphans.len());
    println!();
    println!("=== TOP THREADS ({}) ===", threads.len());
    for (root, size) in threads.iter().take(15) {
        let title = by_id.get(root).map(|p| p.title.as_str()).unwrap_or("?");
        println!("  {} posts | {} | {}", size, root, title);
    }
    println!();
    println!("=== TOP TAGS ===");
    for (tag, count) in tags.iter().take(20) {
        println!("  {:4} {}", count, tag);
    }
    println!();
    println!("=== RECENT ORPHANS (need tagging) ===");
    for p in orphans.iter().take(10) {
        println!("  {} | {:50} | {}B", &p.timestamp, p.title, p.size);
    }
}

fn cmd_publish_tour(geojson_path: &str, outdir: &str) {
    let raw = fs::read_to_string(geojson_path)
        .unwrap_or_else(|e| { eprintln!("Cannot read {}: {}", geojson_path, e); process::exit(1); });
    let geo: serde_json::Value = serde_json::from_str(&raw).unwrap();
    let features = geo["features"].as_array().unwrap();

    let mut shards: Vec<Shard> = Vec::new();
    let mut set = erdfa_publish::ShardSet::new("usa250-trenton-princeton-tour");

    for (i, feat) in features.iter().enumerate() {
        let props = &feat["properties"];
        let name = props["name"].as_str().unwrap_or("unknown");
        let coords = &feat["geometry"]["coordinates"];
        let lon = coords[0].as_f64().unwrap_or(0.0);
        let lat = coords[1].as_f64().unwrap_or(0.0);
        let qid = props["qid"].as_str().unwrap_or("");
        let category = props["category"].as_str().unwrap_or("site");
        let clue = props["geocache_clue"].as_str().unwrap_or("");
        let witness = props["witness"].as_str().unwrap_or("");
        let monster_hole = props["monster_hole"].as_u64();
        let shard_n = props["shard"].as_u64();
        let hecke = props["hecke"].as_u64();
        let bott = props["bott"].as_u64();
        let ipfs_nft = props["ipfs_nft_cid"].as_str().unwrap_or("");
        let ipfs_html = props["ipfs_html_cid"].as_str().unwrap_or("");

        let mut meta = vec![
            ("qid".into(), qid.into()),
            ("category".into(), category.into()),
        ];
        if !clue.is_empty() { meta.push(("geocache_clue".into(), clue.into())); }
        if !witness.is_empty() { meta.push(("witness".into(), witness.into())); }
        if let Some(h) = monster_hole { meta.push(("monster_hole".into(), h.to_string())); }
        if let Some(s) = shard_n { meta.push(("shard".into(), s.to_string())); }
        if let Some(h) = hecke { meta.push(("hecke".into(), h.to_string())); }
        if let Some(b) = bott { meta.push(("bott".into(), b.to_string())); }
        if !ipfs_nft.is_empty() { meta.push(("ipfs_nft".into(), ipfs_nft.into())); }
        if !ipfs_html.is_empty() { meta.push(("ipfs_html".into(), ipfs_html.into())); }

        let component = Component::Group {
            role: "tour-site".into(),
            children: vec![
                Component::MapEntity { name: name.into(), kind: category.into(), x: lon, y: lat, meta },
            ],
        };

        let id = format!("usa250-site-{:02}-{}", i, slugify(name));
        let mut tags = vec!["usa250".into(), "trenton".into(), "nft".into(), category.into()];
        if monster_hole.is_some() { tags.push("geocache".into()); }
        if !qid.is_empty() { tags.push(format!("wikidata:{}", qid)); }

        let shard = Shard::new(&id, component).with_tags(tags);
        set.add(&shard);
        shards.push(shard);
    }

    // Write outputs
    fs::create_dir_all(outdir).ok();

    // 1. CBOR tar bundle
    let tar_path = format!("{}/usa250-trenton-erdfa.tar", outdir);
    let tar_file = fs::File::create(&tar_path).unwrap();
    set.to_tar(&shards, &tar_file).unwrap();
    eprintln!("Wrote {} ({} shards, {} bytes)", tar_path, shards.len(),
        fs::metadata(&tar_path).map(|m| m.len()).unwrap_or(0));

    // 2. Individual CBOR shards as JSON (for web/blocks/)
    let blocks_dir = format!("{}/blocks", outdir);
    fs::create_dir_all(&blocks_dir).ok();
    for shard in &shards {
        let json = serde_json::to_string_pretty(&shard).unwrap();
        let path = format!("{}/{}.json", blocks_dir, shard.cid);
        fs::write(&path, &json).ok();
    }
    // Manifest
    let manifest = serde_json::to_string_pretty(&set).unwrap();
    fs::write(format!("{}/manifest.json", blocks_dir), &manifest).ok();
    eprintln!("Wrote {}/manifest.json + {} block files", blocks_dir, shards.len());

    // 3. HTML gallery (self-contained, archive.org friendly)
    let gallery_path = format!("{}/usa250-trenton-gallery.html", outdir);
    let mut html = String::from(r#"<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>USA250 Trenton-Princeton Historical Tour &mdash; eRDFa NFT Series</title>
<meta name="description" content="20 geocache NFT sites for the 250th anniversary of the United States, Trenton-Princeton NJ. Monster Group coordinates, Wikidata, IPFS.">
<style>*{box-sizing:border-box;margin:0;padding:0}body{font:16px/1.6 system-ui,sans-serif;max-width:960px;margin:2rem auto;padding:0 1rem;background:#0d1117;color:#c9d1d9}a{color:#58a6ff}h1,h2{margin:1rem 0 .5rem;color:#f0f6fc}.shard-card{border:1px solid #30363d;border-radius:8px;padding:1rem;margin:1rem 0}.tag{display:inline-block;background:#1f6feb33;color:#58a6ff;padding:2px 8px;border-radius:12px;font-size:12px;margin:2px}dl{display:grid;grid-template-columns:auto 1fr;gap:.3rem 1rem;margin:.5rem 0}dt{font-weight:600;color:#8b949e}dd{color:#c9d1d9}.coords{font-family:monospace;color:#7ee787}</style>
</head><body>
<h1>&#128509; USA250 Trenton-Princeton Historical Tour</h1>
<p>20 geocache NFT sites for the 250th anniversary of the United States. Each site mapped to <a href="https://en.wikipedia.org/wiki/Monster_group">Monster Group</a> coordinates, enriched with Wikidata, witnessed with zkTLS, pinned to IPFS.</p>
<p>eRDFa CBOR shards &middot; DA51 tagged &middot; archive.org collection</p>
<hr style="border-color:#30363d;margin:1rem 0">
"#);
    for shard in &shards {
        html.push_str(&format!("<article class=\"shard-card\" id=\"{}\">\n", shard.id));
        html.push_str(&erdfa_publish::render::render_html(shard));
        html.push_str(&format!("<p><code>{}</code></p>\n<div>", shard.cid));
        for tag in &shard.tags {
            html.push_str(&format!("<span class=\"tag\">{}</span>", tag));
        }
        html.push_str("</div>\n</article>\n");
    }
    html.push_str(&format!("<footer><p>{} shards &middot; generated {}</p></footer></body></html>",
        shards.len(), chrono::Utc::now().format("%Y-%m-%dT%H:%M:%SZ")));
    fs::write(&gallery_path, &html).unwrap();
    eprintln!("Wrote {}", gallery_path);

    // 4. archive.org metadata XML
    let meta_path = format!("{}/usa250-trenton-erdfa_meta.xml", outdir);
    let meta_xml = format!(r#"<?xml version="1.0" encoding="UTF-8"?>
<metadata>
  <identifier>usa250-trenton-princeton-erdfa-nft</identifier>
  <title>USA250 Trenton-Princeton Historical Tour -- eRDFa NFT Series</title>
  <description>20 geocache NFT sites for the 250th anniversary of the United States, covering Trenton and Princeton, NJ. Sites of Washington's Crossing, Battle of Trenton (1776), and Battle of Princeton (1777). Each site mapped to Monster Group coordinates (196,883-dimensional), enriched with Wikidata QIDs, witnessed with zkTLS, and pinned to IPFS. Encoded as DA51-tagged CBOR shards using the eRDFa semantic component format.</description>
  <creator>meta-introspector</creator>
  <date>{date}</date>
  <subject>USA250</subject>
  <subject>American Revolution</subject>
  <subject>Trenton NJ</subject>
  <subject>Princeton NJ</subject>
  <subject>geocache</subject>
  <subject>NFT</subject>
  <subject>Monster Group</subject>
  <subject>eRDFa</subject>
  <subject>CBOR</subject>
  <subject>DASL</subject>
  <subject>Wikidata</subject>
  <subject>IPFS</subject>
  <subject>semantic web</subject>
  <mediatype>data</mediatype>
  <collection>opensource_media</collection>
  <licenseurl>https://creativecommons.org/licenses/by-sa/4.0/</licenseurl>
  <notes>{count} CBOR shards in DA51 tar archive + HTML gallery + JSON blocks</notes>
</metadata>"#, date = chrono::Utc::now().format("%Y-%m-%d"), count = shards.len());
    fs::write(&meta_path, &meta_xml).unwrap();
    eprintln!("Wrote {}", meta_path);

    // Summary
    println!("=== USA250 Trenton eRDFa Series ===");
    println!("Shards:   {}", shards.len());
    println!("Tar:      {}", tar_path);
    println!("Gallery:  {}", gallery_path);
    println!("Metadata: {}", meta_path);
    println!("Blocks:   {}/", blocks_dir);
    println!();
    println!("Upload to archive.org:");
    println!("  ia upload usa250-trenton-princeton-erdfa-nft \\");
    println!("    {} \\", tar_path);
    println!("    {} \\", gallery_path);
    println!("    --metadata=\"collection:opensource_media\" \\");
    println!("    --metadata=\"title:USA250 Trenton-Princeton eRDFa NFT Series\" \\");
    println!("    --metadata=\"mediatype:data\"");
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("kantpaste <command> [args]");
        eprintln!("  list [N]                         — list recent N pastes (default 20)");
        eprintln!("  show <id>                        — show paste content");
        eprintln!("  thread <id>                      — show thread tree (local)");
        eprintln!("  replies <id>                     — show thread via API with content");
        eprintln!("  post <title> [--reply-to ID] [--kw a,b]  — create paste from stdin");
        eprintln!("  route <id> <exchange> <key>      — publish paste to RabbitMQ");
        eprintln!("  tags [tag]                       — list all tags or filter by tag");
        eprintln!("  search <query>                   — search titles and keywords");
        eprintln!("  garden                           — overview: threads, tags, orphans");
        eprintln!("  delete <id>                      — move paste to .trash");
        eprintln!("  restore <id>                     — restore from .trash");
        eprintln!("  trash                            — list trashed pastes");
        eprintln!("  export <id> [--thread] [--format html|json]  — export paste/thread");
        eprintln!("  import <file> [--reply-to ID]    — import HTML/text paste");
        eprintln!("  publish-tour [geojson] [outdir]   — package tour as eRDFa shards for archive.org");
        process::exit(1);
    }

    match args[1].as_str() {
        "list" => {
            let n: usize = args.get(2).and_then(|s| s.parse().ok()).unwrap_or(20);
            cmd_list(n);
        }
        "show" => {
            let id = args.get(2).unwrap_or_else(|| { eprintln!("Usage: kantpaste show <id>"); process::exit(1); });
            cmd_show(id);
        }
        "thread" => {
            let id = args.get(2).unwrap_or_else(|| { eprintln!("Usage: kantpaste thread <id>"); process::exit(1); });
            cmd_thread(id);
        }
        "replies" => {
            let id = args.get(2).unwrap_or_else(|| { eprintln!("Usage: kantpaste replies <id>"); process::exit(1); });
            cmd_replies(id);
        }
        "tags" => {
            cmd_tags(args.get(2).map(|s| s.as_str()));
        }
        "search" => {
            let q = args.get(2).unwrap_or_else(|| { eprintln!("Usage: kantpaste search <query>"); process::exit(1); });
            cmd_search(q);
        }
        "garden" => {
            cmd_garden();
        }
        "delete" | "rm" => {
            let id = args.get(2).unwrap_or_else(|| { eprintln!("Usage: kantpaste delete <id>"); process::exit(1); });
            cmd_delete(id);
        }
        "restore" => {
            let id = args.get(2).unwrap_or_else(|| { eprintln!("Usage: kantpaste restore <id>"); process::exit(1); });
            cmd_restore(id);
        }
        "trash" => {
            cmd_trash_list();
        }
        "post" => {
            let title = args.get(2).unwrap_or_else(|| { eprintln!("Usage: kantpaste post <title>"); process::exit(1); });
            let mut reply_to = None;
            let mut keywords = Vec::new();
            let mut i = 3;
            while i < args.len() {
                match args[i].as_str() {
                    "--reply-to" => { reply_to = args.get(i + 1).map(|s| s.as_str()); i += 2; }
                    "--kw" => { keywords = args.get(i + 1).map(|s| s.split(',').map(|k| k.trim().to_string()).collect()).unwrap_or_default(); i += 2; }
                    _ => { i += 1; }
                }
            }
            let mut content = String::new();
            std::io::Read::read_to_string(&mut std::io::stdin(), &mut content).unwrap();
            cmd_post(title, &content, reply_to, &keywords);
        }
        "route" => {
            if args.len() < 5 {
                eprintln!("Usage: kantpaste route <id> <exchange> <routing_key>");
                process::exit(1);
            }
            cmd_route(&args[2], &args[3], &args[4]);
        }
        "export" => {
            let id = args.get(2).unwrap_or_else(|| { eprintln!("Usage: kantpaste export <id> [--thread] [--format html|json]"); process::exit(1); });
            let thread = args.iter().any(|a| a == "--thread");
            let fmt = args.iter().position(|a| a == "--format").and_then(|i| args.get(i + 1)).map(|s| s.as_str()).unwrap_or("html");
            cmd_export(id, thread, fmt);
        }
        "import" => {
            let path = args.get(2).unwrap_or_else(|| { eprintln!("Usage: kantpaste import <file> [--reply-to ID]"); process::exit(1); });
            let reply_to = args.iter().position(|a| a == "--reply-to").and_then(|i| args.get(i + 1)).map(|s| s.as_str());
            cmd_import(path, reply_to);
        }
        "publish-tour" => {
            let geojson = args.get(2).map(|s| s.as_str())
                .unwrap_or("/mnt/data1/time-2026/03-march/13/usa250-trenton/tour.geojson");
            let outdir = args.get(3).map(|s| s.as_str()).unwrap_or(".");
            cmd_publish_tour(geojson, outdir);
        }
        _ => { eprintln!("Unknown command: {}", args[1]); process::exit(1); }
    }
}
