// MCP (Model Context Protocol) server — exposes pastebin functionality as MCP tools
// JSON-RPC 2.0 over HTTP POST
// Protocol: https://modelcontextprotocol.io

use actix_web::{web, HttpRequest, HttpResponse, Result};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::env;
use std::sync::Mutex;

// ─── JSON-RPC 2.0 Types ──────────────────────────────────────────────────

#[derive(Deserialize)]
pub struct JsonRpcRequest {
    pub jsonrpc: String,
    pub id: Value, // string | number | null
    pub method: String,
    #[serde(default)]
    pub params: Option<Value>,
}

#[derive(Serialize)]
pub struct JsonRpcResponse {
    pub jsonrpc: String,
    pub id: Value,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<JsonRpcError>,
}

#[derive(Serialize)]
pub struct JsonRpcError {
    pub code: i32,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<Value>,
}

// ─── MCP Tool Definitions ─────────────────────────────────────────────────

fn mcp_tools() -> Vec<McpToolDef> {
    vec![
        McpToolDef {
            name: "search_pastes".into(),
            description: "Search pastebin content and metadata. Searches both paste content and DOCS directories.".into(),
            input_schema: json!({
                "type": "object",
                "properties": {
                    "query": { "type": "string", "description": "Search query" },
                    "limit": { "type": "integer", "description": "Max results (default 10)", "default": 10 },
                    "search_dirs": { "type": "boolean", "description": "Include DOCS directory search", "default": true }
                },
                "required": ["query"]
            }),
        },
        McpToolDef {
            name: "create_paste".into(),
            description: "Create a new paste. Content is posted to the pastebin for sharing or indexing.".into(),
            input_schema: json!({
                "type": "object",
                "properties": {
                    "title": { "type": "string", "description": "Paste title" },
                    "content": { "type": "string", "description": "Paste content" },
                    "keywords": { "type": "string", "description": "Comma-separated keywords" }
                },
                "required": ["content"]
            }),
        },
        McpToolDef {
            name: "get_paste".into(),
            description: "Retrieve a paste by its ID. Returns content, metadata, and timestamps.".into(),
            input_schema: json!({
                "type": "object",
                "properties": {
                    "paste_id": { "type": "string", "description": "Paste ID or filename" }
                },
                "required": ["paste_id"]
            }),
        },
        McpToolDef {
            name: "browse_pastes".into(),
            description: "Browse all pastes with optional search filter. Returns metadata listing.".into(),
            input_schema: json!({
                "type": "object",
                "properties": {
                    "query": { "type": "string", "description": "Optional search filter" },
                    "limit": { "type": "integer", "description": "Max results (default 20)", "default": 20 }
                }
            }),
        },
        McpToolDef {
            name: "analyze_flake".into(),
            description: "Analyze a flake.nix file and return structured data: inputs, outputs, packages, devShells, warnings.".into(),
            input_schema: json!({
                "type": "object",
                "properties": {
                    "path": { "type": "string", "description": "Path to flake.nix file" }
                },
                "required": ["path"]
            }),
        },
        McpToolDef {
            name: "find_flakes".into(),
            description: "Find and analyze all flake.nix files in a directory tree.".into(),
            input_schema: json!({
                "type": "object",
                "properties": {
                    "directory": { "type": "string", "description": "Root directory to search (default ~/dasl)" },
                    "max_depth": { "type": "integer", "description": "Max directory depth (default 4)" }
                }
            }),
        },
    ]
}
#[derive(Serialize)]
struct McpToolDef {
    name: String,
    description: String,
    input_schema: Value,
}

// ─── MCP Handler ──────────────────────────────────────────────────────────

pub async fn mcp_handler(
    body: web::Json<JsonRpcRequest>,
    _req: HttpRequest,
) -> Result<HttpResponse> {
    let req = body.into_inner();
    let id = req.id.clone();

    let result = match req.method.as_str() {
        "initialize" => handle_initialize(&req.params),
        "tools/list" => handle_tools_list(),
        "tools/call" => handle_tools_call(&req.params).await,
        "resources/list" => Ok(json!({
            "resources": [
                {
                    "uri": "pastebin://recent",
                    "name": "Recent Pastes",
                    "description": "List of recent paste entries",
                    "mimeType": "application/json",
                }
            ]
        })),
        "resources/read" => handle_resources_read(&req.params).await,
        _ => {
            let resp = JsonRpcResponse {
                jsonrpc: "2.0".to_string(),
                id,
                result: None,
                error: Some(JsonRpcError {
                    code: -32601,
                    message: format!("Method not found: {}", req.method),
                    data: None,
                }),
            };
            return Ok(HttpResponse::Ok().json(resp));
        }
    };

    match result {
        Ok(r) => {
            let resp = JsonRpcResponse {
                jsonrpc: "2.0".to_string(),
                id,
                result: Some(r),
                error: None,
            };
            Ok(HttpResponse::Ok().json(resp))
        }
        Err(e) => {
            let resp = JsonRpcResponse {
                jsonrpc: "2.0".to_string(),
                id,
                result: None,
                error: Some(JsonRpcError {
                    code: -32603,
                    message: e,
                    data: None,
                }),
            };
            Ok(HttpResponse::Ok().json(resp))
        }
    }
}

fn handle_initialize(_params: &Option<Value>) -> Result<Value, String> {
    Ok(json!({
        "protocolVersion": "0.1.0",
        "capabilities": {
            "tools": {},
            "resources": {}
        },
        "serverInfo": {
            "name": "kant-pastebin-mcp",
            "version": "0.1.0"
        }
    }))
}

fn handle_tools_list() -> Result<Value, String> {
    Ok(json!({
        "tools": mcp_tools()
    }))
}

async fn handle_tools_call(params: &Option<Value>) -> Result<Value, String> {
    let p = params
        .as_ref()
        .ok_or_else(|| "Missing params".to_string())?;
    let name = p
        .get("name")
        .and_then(|v| v.as_str())
        .ok_or_else(|| "Missing tool name".to_string())?;
    let args: HashMap<String, Value> = p
        .get("arguments")
        .and_then(|v| v.as_object())
        .cloned()
        .unwrap_or_default()
        .into_iter()
        .collect();

    match name {
        "search_pastes" => handle_mcp_search(args).await,
        "create_paste" => handle_mcp_create_paste(args).await,
        "get_paste" => handle_mcp_get_paste(args).await,
        "browse_pastes" => handle_mcp_browse(args).await,
        "analyze_flake" => handle_mcp_analyze_flake(args),
        "find_flakes" => handle_mcp_find_flakes(args),
        _ => Err(format!("Unknown tool: {}", name)),
    }
}

async fn handle_mcp_search(args: HashMap<String, Value>) -> Result<Value, String> {
    let query = args
        .get("query")
        .and_then(|v| v.as_str())
        .ok_or_else(|| "Missing 'query' parameter".to_string())?;
    let limit = args.get("limit").and_then(|v| v.as_i64()).unwrap_or(10) as usize;
    let search_dirs = args
        .get("search_dirs")
        .and_then(|v| v.as_bool())
        .unwrap_or(true);

    // Call our own HTTP API
    let base_url = env::var("BASE_URL").unwrap_or_else(|_| "http://127.0.0.1:8090".to_string());
    let url = format!(
        "{}/api/search?q={}&dirs={}&limit={}",
        base_url,
        query,
        if search_dirs { "1" } else { "0" },
        limit
    );

    let client = reqwest::blocking::Client::new();
    let resp = client
        .get(&url)
        .send()
        .map_err(|e| format!("Search request failed: {}", e))?;
    let body: Value = resp
        .json()
        .map_err(|e| format!("Search parse failed: {}", e))?;

    Ok(json!({
        "content": serde_json::to_string_pretty(&body).unwrap_or_default(),
        "isError": false
    }))
}

async fn handle_mcp_create_paste(args: HashMap<String, Value>) -> Result<Value, String> {
    let content = args
        .get("content")
        .and_then(|v| v.as_str())
        .ok_or_else(|| "Missing 'content' parameter".to_string())?;
    let title = args.get("title").and_then(|v| v.as_str()).unwrap_or("MCP");
    let keywords = args.get("keywords").and_then(|v| v.as_str()).unwrap_or("");

    let base_url = env::var("BASE_URL").unwrap_or_else(|_| "http://127.0.0.1:8090".to_string());
    let url = format!("{}/paste", base_url);

    let client = reqwest::blocking::Client::new();
    let payload = json!({
        "title": title,
        "content": content,
        "keywords": keywords
    });
    let resp = client
        .post(&url)
        .json(&payload)
        .send()
        .map_err(|e| format!("Create paste failed: {}", e))?;
    let body: Value = resp
        .json()
        .map_err(|e| format!("Parse response failed: {}", e))?;

    Ok(json!({
        "content": serde_json::to_string_pretty(&body).unwrap_or_default(),
        "isError": false
    }))
}

async fn handle_mcp_get_paste(args: HashMap<String, Value>) -> Result<Value, String> {
    let paste_id = args
        .get("paste_id")
        .and_then(|v| v.as_str())
        .ok_or_else(|| "Missing 'paste_id' parameter".to_string())?;

    let base_url = env::var("BASE_URL").unwrap_or_else(|_| "http://127.0.0.1:8090".to_string());

    // Try raw first (returns content with metadata)
    let client = reqwest::blocking::Client::new();
    let raw_url = format!("{}/raw/{}", base_url, paste_id);
    let raw_resp = client.get(&raw_url).send().ok();
    let raw_content = raw_resp.and_then(|r| r.text().ok()).unwrap_or_default();

    // Also get metadata via paste endpoint
    let paste_url = format!("{}/paste/{}", base_url, paste_id);
    let paste_resp = client.get(&paste_url).send().ok();
    let paste_html = paste_resp.and_then(|r| r.text().ok()).unwrap_or_default();

    Ok(json!({
        "content": format!("=== Raw Content ===\n{}\n\n=== HTML View (first 500 chars) ===\n{}",
            &raw_content[..raw_content.len().min(5000)],
            &paste_html[..paste_html.len().min(500)]),
        "isError": false
    }))
}

async fn handle_mcp_browse(args: HashMap<String, Value>) -> Result<Value, String> {
    let query = args.get("query").and_then(|v| v.as_str()).unwrap_or("");
    let limit = args.get("limit").and_then(|v| v.as_i64()).unwrap_or(20) as usize;

    let base_url = env::var("BASE_URL").unwrap_or_else(|_| "http://127.0.0.1:8090".to_string());
    let mut url = format!("{}/api/search?limit={}&dirs=0", base_url, limit);
    if !query.is_empty() {
        url.push_str(&format!("&q={}", query));
    }

    let client = reqwest::blocking::Client::new();
    let resp = client
        .get(&url)
        .send()
        .map_err(|e| format!("Browse request failed: {}", e))?;
    let body: Value = resp.json().map_err(|e| format!("Parse failed: {}", e))?;

    Ok(json!({
        "content": serde_json::to_string_pretty(&body).unwrap_or_default(),
        "isError": false
    }))
}

fn handle_mcp_analyze_flake(args: HashMap<String, Value>) -> Result<Value, String> {
    let path = args
        .get("path")
        .and_then(|v| v.as_str())
        .ok_or_else(|| "Missing 'path' parameter".to_string())?;

    let analysis = crate::nix_skill::analyze_flake(path)?;

    Ok(json!({
        "content": serde_json::to_string_pretty(&analysis).unwrap_or_default(),
        "isError": false
    }))
}

fn handle_mcp_find_flakes(args: HashMap<String, Value>) -> Result<Value, String> {
    let directory = args
        .get("directory")
        .and_then(|v| v.as_str())
        .unwrap_or("~/dasl")
        .to_string();
    let max_depth: usize = args.get("max_depth").and_then(|v| v.as_i64()).unwrap_or(4) as usize;

    let dir = directory.replace(
        "~",
        &env::var("HOME").unwrap_or_else(|_| "/home/mdupont".to_string()),
    );

    // Find all flake.nix files up to max_depth
    let mut paths = Vec::new();
    let mut dirs_to_check = vec![(dir.clone(), 0)];

    while let Some((current_dir, depth)) = dirs_to_check.pop() {
        if depth > max_depth {
            continue;
        }
        let entries = match std::fs::read_dir(&current_dir) {
            Ok(e) => e,
            Err(_) => continue,
        };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() && depth < max_depth {
                dirs_to_check.push((path.display().to_string(), depth + 1));
            } else if path.is_file() && path.file_name().map_or(false, |n| n == "flake.nix") {
                paths.push(path.display().to_string());
            }
        }
    }

    let analyses = crate::nix_skill::analyze_flakes(&paths);

    Ok(json!({
        "content": serde_json::to_string_pretty(&json!({
            "total_flakes": analyses.len(),
            "directory": dir,
            "max_depth": max_depth,
            "flakes": analyses,
        })).unwrap_or_default(),
        "isError": false
    }))
}

async fn handle_resources_read(params: &Option<Value>) -> Result<Value, String> {
    let p = params
        .as_ref()
        .ok_or_else(|| "Missing params".to_string())?;
    let uri = p
        .get("uri")
        .and_then(|v| v.as_str())
        .ok_or_else(|| "Missing URI".to_string())?;

    match uri {
        "pastebin://recent" => {
            let base_url =
                env::var("BASE_URL").unwrap_or_else(|_| "http://127.0.0.1:8090".to_string());
            let url = format!("{}/api/search?limit=20&dirs=0&q=", base_url);

            let client = reqwest::blocking::Client::new();
            let resp = client
                .get(&url)
                .send()
                .map_err(|e| format!("Request failed: {}", e))?;
            let body: Value = resp.json().map_err(|e| format!("Parse failed: {}", e))?;

            Ok(json!({
                "contents": [{
                    "uri": uri,
                    "mimeType": "application/json",
                    "text": serde_json::to_string_pretty(&body).unwrap_or_default()
                }]
            }))
        }
        _ => Err(format!("Unknown resource: {}", uri)),
    }
}
