//! agent-fabric — the one unit that joins the pastebin, the IPLD pools, IPFS,
//! postgres, git mounts, the Cloudflare API, the Durable Object board, the GPU
//! and the relay into a single task plane for agents.
//!
//!     agent-fabric [serve|gate|capabilities|sync|version]
//!
//! Everything it needs is declared in `fabric/nix/agent-fabric.nix`, which also
//! lists the units it is ordered against. `agent-fabric gate` is the
//! `ExecStartPre` that refuses to start when one of them is not answering.

#[path = "fabric/mod.rs"]
mod fabric;

use std::io::Write;
use std::net::TcpListener;
use std::os::unix::net::UnixListener;
use std::sync::Arc;
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use serde_json::{json, Value};

use fabric::adapters::{self, Deps};
use fabric::blocks::Blocks;
use fabric::chat::Relay;
use fabric::do_sync::DoSync;
use fabric::http::{self, Handler, Request, Response};
use fabric::protocol::{self, Event};
use fabric::store::{self, Store};
use fabric::VERSION;

struct Ctx {
    store: Store,
    blocks: Blocks,
    relay: Relay,
    deps: Deps,
    board: DoSync,
    lease_secs: u64,
}

fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

fn env_u64(k: &str, default: u64) -> u64 {
    std::env::var(k)
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(default)
}

fn agent_of(body: &Value) -> String {
    body.get("agent")
        .and_then(|a| a.as_str())
        .unwrap_or("operator")
        .to_string()
}

/// The single place a task can move: build the event, apply it, record it,
/// then mirror it. Mirroring is best effort and its failure is reported in the
/// response rather than silently dropped.
fn apply_event(ctx: &Ctx, ev: Event) -> Response {
    apply_event_with(ctx, ev, ctx.lease_secs)
}

/// As `apply_event`, but with the lease the caller asked for. A claim may ask
/// for a shorter lease than the default (never longer); that is what makes
/// expiry observable in a test instead of an hour away.
fn apply_event_with(ctx: &Ctx, ev: Event, lease_secs: u64) -> Response {
    let ts = now();
    match store::ingest(&ctx.store, &ev, ts, lease_secs) {
        Err(e) => Response::error(409, e),
        Ok(task) => {
            let mut relay_status = json!("no task room".to_string());
            if let Some(t) = &task {
                let room = protocol::task_room(&t.id);
                let line = serde_json::to_string(&ev.line).unwrap_or_default();
                relay_status = match ctx.relay.post(&room, &line) {
                    Ok(cursor) => json!({"ok": true, "cursor": cursor, "room": room}),
                    Err(e) => json!({"ok": false, "error": e, "room": room}),
                };
            }
            let seq = ctx.store.max_seq().unwrap_or(0);
            Response::json(
                200,
                &json!({
                    "ok": true,
                    "seq": seq,
                    "event": ev.line,
                    "block_cid": ev.block_cid,
                    "task": task.map(|t| t.value),
                    "relay": relay_status,
                }),
            )
        }
    }
}

fn pull_relay_for(ctx: &Ctx, task: &str) -> Result<usize, String> {
    let room = protocol::task_room(task);
    let key = format!("relay_cursor:{task}");
    let cursor: i64 = ctx
        .store
        .meta(&key)?
        .and_then(|v| v.parse().ok())
        .unwrap_or(0);
    let (next, lines, truncated) = ctx.relay.fetch(&room, cursor)?;
    let mut applied = 0;
    for line in lines {
        match protocol::verify_line(&line) {
            Ok(ev) => {
                if ctx.store.event_line(&ev.id)?.is_some() {
                    continue;
                }
                if ev.task.as_deref() != Some(task) {
                    continue; // a line for another task is not ours to apply
                }
                if store::ingest(&ctx.store, &ev, now(), ctx.lease_secs).is_ok() {
                    applied += 1;
                }
            }
            Err(e) => eprintln!("fabric: dropped relay line: {e}"),
        }
    }
    if truncated {
        eprintln!("fabric: relay trimmed room {room}; resuming from {next}");
    }
    ctx.store.set_meta(&key, &next.to_string())?;
    Ok(applied)
}

fn route(ctx: &Ctx, req: Request) -> Response {
    let segs: Vec<&str> = req
        .path
        .trim_start_matches('/')
        .split('/')
        .filter(|s| !s.is_empty())
        .collect();
    match (req.method.as_str(), segs.as_slice()) {
        ("GET", ["health"]) => health(ctx),
        ("GET", ["capabilities"]) => {
            let (failures, report) = adapters::gate(&ctx.store, &ctx.blocks, &ctx.relay, &ctx.deps);
            Response::json(200, &json!({"ok": failures.is_empty(), "failures": failures, "deps": report}))
        }
        ("GET", ["tasks"]) => {
            let state = req.param("state").unwrap_or("");
            match ctx.store.tasks(state) {
                Ok(tasks) => Response::json(200, &json!({"ok": true, "tasks": tasks})),
                Err(e) => Response::error(500, e),
            }
        }
        ("POST", ["tasks"]) => {
            let body = match req.json() {
                Ok(b) => b,
                Err(e) => return Response::error(400, e),
            };
            let ev = protocol::make_event(
                "task.offer",
                None,
                None,
                &agent_of(&body),
                now(),
                json!({
                    "title": body.get("title").and_then(|t| t.as_str()).unwrap_or("untitled"),
                    "kind": body.get("kind").and_then(|k| k.as_str()).unwrap_or("general"),
                    "payload": body.get("payload").cloned().unwrap_or(Value::Null),
                }),
            );
            apply_event(ctx, ev)
        }
        ("GET", ["tasks", id]) => match ctx.store.task(id) {
            Ok(Some(t)) => Response::json(200, &json!({"ok": true, "task": t.value})),
            Ok(None) => Response::error(404, format!("no task {id}")),
            Err(e) => Response::error(500, e),
        },
        ("POST", ["tasks", id, action]) => match *action {
            "claim" | "start" | "result" | "cancel" | "progress" | "renew" => {
                let body = match req.json() {
                    Ok(b) => b,
                    Err(e) => return Response::error(400, e),
                };
                let kind = format!("task.{action}");
                let mut payload = body.clone();
                if let Some(secs) = body.get("lease_secs") {
                    payload["lease_secs"] = secs.clone();
                }
                if *action == "result" {
                    // A result can be a block the agent already stored, or text
                    // the fabric stores for it.
                    if payload.get("result_cid").is_none() {
                        if let Some(text) = body.get("result").and_then(|r| r.as_str()) {
                            match ctx.blocks.put(text.as_bytes()) {
                                Ok(cid) => {
                                    payload["result_cid"] = json!(cid);
                                    payload["result_block"] = json!(true);
                                }
                                Err(e) => {
                                    return Response::error(502, format!("cannot store result: {e}"))
                                }
                            }
                        }
                    }
                }
                let lease = match body.get("lease_secs").and_then(|l| l.as_u64()) {
                    Some(requested) if requested > 0 => requested.min(ctx.lease_secs),
                    _ => ctx.lease_secs,
                };
                let ev = protocol::make_event(kind.as_str(), Some(id), None, &agent_of(&body), now(), payload);
                apply_event_with(ctx, ev, lease)
            }
            "chat" => {
                let body = match req.json() {
                    Ok(b) => b,
                    Err(e) => return Response::error(400, e),
                };
                let text = body.get("text").and_then(|t| t.as_str()).unwrap_or("");
                if text.is_empty() {
                    return Response::error(400, "chat needs text");
                }
                let text_cid = match ctx.blocks.put(text.as_bytes()) {
                    Ok(cid) => cid,
                    Err(e) => return Response::error(502, format!("cannot store chat block: {e}")),
                };
                let ev = protocol::make_event(
                    "chat.say",
                    Some(id),
                    Some(&protocol::task_room(id)),
                    &agent_of(&body),
                    now(),
                    json!({
                        "text": text,
                        "text_cid": text_cid,
                        "text_digest": fabric::canon::kant_digest_hex(text.as_bytes()),
                    }),
                );
                let room = protocol::task_room(id);
                let line = serde_json::to_string(&ev.line).unwrap_or_default();
                let relay = match ctx.relay.post(&room, &line) {
                    Ok(c) => json!({"ok": true, "cursor": c}),
                    Err(e) => json!({"ok": false, "error": e}),
                };
                match store::ingest(&ctx.store, &ev, now(), ctx.lease_secs) {
                    Ok(_) => Response::json(
                        200,
                        &json!({"ok": true, "event": ev.line, "block_cid": ev.block_cid, "relay": relay}),
                    ),
                    Err(e) => Response::error(409, e),
                }
            }
            _ => Response::error(404, format!("no action {action}")),
        },
        ("GET", ["tasks", id, "chat"]) => {
            if let Err(e) = pull_relay_for(ctx, id) {
                eprintln!("fabric: relay pull for {id} failed: {e}");
            }
            let since: i64 = req.param("since").and_then(|s| s.parse().ok()).unwrap_or(0);
            match ctx.store.chat(id, since) {
                Ok(lines) => Response::json(200, &json!({"ok": true, "task": id, "messages": lines})),
                Err(e) => Response::error(500, e),
            }
        }
        ("GET", ["events"]) => {
            let since: i64 = req.param("since").and_then(|s| s.parse().ok()).unwrap_or(0);
            let limit: i64 = req.param("limit").and_then(|s| s.parse().ok()).unwrap_or(200);
            match ctx.store.events_since(since, limit) {
                Ok(events) => Response::json(200, &json!({"ok": true, "events": events})),
                Err(e) => Response::error(500, e),
            }
        }
        ("POST", ["events"]) => {
            // Accept an event from any transport. It is verified, not trusted.
            let text = match std::str::from_utf8(&req.body) {
                Ok(t) => t,
                Err(e) => return Response::error(400, e.to_string()),
            };
            match protocol::verify_line(text.trim()) {
                Err(e) => Response::error(400, format!("refused: {e}")),
                Ok(ev) => apply_event(ctx, ev),
            }
        }
        ("POST", ["blocks"]) => {
            if req.body.len() > 1024 * 1024 {
                return Response::error(413, "block larger than 1 MiB");
            }
            match ctx.blocks.put(&req.body) {
                Err(e) => Response::error(502, e),
                Ok(cid) => {
                    let pool = ctx.blocks.pool_put(&cid, &req.body);
                    Response::json(
                        200,
                        &json!({
                            "ok": true,
                            "cid": cid,
                            "kant_digest": fabric::canon::kant_digest_hex(&req.body),
                            "pool": match &pool {
                                Ok(p) => json!({"ok": true, "path": p}),
                                Err(e) => json!({"ok": false, "error": e}),
                            },
                            "gateway": format!("{}/ipfs/{cid}", ctx.blocks.gateway),
                        }),
                    )
                }
            }
        }
        ("GET", ["blocks", cid]) => match ctx.blocks.get(cid) {
            Ok(bytes) => Response::bytes(200, bytes),
            Err(e) => Response::error(404, e),
        },
        ("GET", ["peers"]) => match ctx.store.agents() {
            Ok(agents) => Response::json(
                200,
                &json!({
                    "ok": true,
                    "host": "local",
                    "agents": agents,
                    "gpu": adapters::gpu(),
                    "git_mounts": adapters::git_mounts(&ctx.deps.git_mounts),
                    "pool": ctx.blocks.pool,
                }),
            ),
            Err(e) => Response::error(500, e),
        },
        ("POST", ["sync"]) => match sync_once(ctx) {
            Ok(v) => Response::json(200, &json!({"ok": true, "sync": v})),
            Err(e) => Response::error(502, e),
        },
        _ => Response::error(404, format!("no route {} {}", req.method, req.path)),
    }
}

fn health(ctx: &Ctx) -> Response {
    let (events, tasks) = ctx.store.count().unwrap_or((-1, -1));
    let relay = ctx.relay.health().is_ok();
    Response::json(
        200,
        &json!({
            "ok": true,
            "service": "agent-fabric",
            "version": VERSION,
            "database": ctx.store.db,
            "events": events,
            "tasks": tasks,
            "relay": {"url": ctx.relay.url, "ok": relay},
            "ipfs": {"gateway": ctx.blocks.gateway, "node": ctx.blocks.ipfs},
            "ipld_pool": ctx.blocks.pool,
            "board": {"url": ctx.board.base, "enabled": ctx.board.enabled()},
            "lease_secs": ctx.lease_secs,
        }),
    )
}

fn sync_once(ctx: &Ctx) -> Result<Value, String> {
    let push = ctx.board.push(&ctx.store)?;
    let pull = ctx.board.pull(&ctx.store, now(), ctx.lease_secs)?;
    Ok(json!({
        "pushed": push.pushed,
        "do_cursor": push.cursor,
        "applied": pull.applied,
        "duplicates": pull.duplicates,
        "rejected": pull.rejected,
        "pull_cursor": pull.cursor,
    }))
}

/// Lease expiry runs on its own thread at its own interval. It must not wait
/// behind a Durable Object or a relay that is slow to answer: a stalled mirror
/// once pushed the sweep 18 seconds late, which is how a live task looked
/// leased long after it was not. Nothing network-bound shares this thread.
fn sweeper(ctx: Arc<Ctx>, interval: Duration) {
    loop {
        thread::sleep(interval);
        match store::sweep_leases(&ctx.store, now(), ctx.lease_secs) {
            Ok(n) if n > 0 => eprintln!("fabric: re-offered {n} task(s) with expired leases"),
            Ok(_) => {}
            Err(e) => eprintln!("fabric: lease sweep failed: {e}"),
        }
    }
}

/// Mirrors and relay ingestion share a thread, because both are network-bound
/// and both are only as good as the far end.
fn syncer(ctx: Arc<Ctx>, interval: Duration) {
    loop {
        thread::sleep(interval);
        if ctx.board.enabled() {
            if let Err(e) = sync_once(&ctx) {
                eprintln!("fabric: durable object sync failed: {e}");
            }
        }
        if let Ok(tasks) = ctx.store.tasks("") {
            for t in tasks {
                let state = t["state"].as_str().unwrap_or("");
                if protocol::is_terminal(state) {
                    continue;
                }
                if let Some(id) = t["id"].as_str() {
                    if let Err(e) = pull_relay_for(&ctx, id) {
                        eprintln!("fabric: relay pull for {id} failed: {e}");
                    }
                }
            }
        }
    }
}

fn serve(ctx: Arc<Ctx>) -> Result<(), String> {
    let addr = std::env::var("FABRIC_HTTP").unwrap_or_else(|_| "127.0.0.1:8190".into());
    let socket_path =
        std::env::var("FABRIC_SOCKET").unwrap_or_else(|_| "/run/agent-fabric/fabric.sock".into());
    let interval = Duration::from_secs(env_u64("FABRIC_TICK_SECS", 5));
    let sync_interval = Duration::from_secs(env_u64("FABRIC_SYNC_SECS", 5));

    {
        let ctx = ctx.clone();
        thread::spawn(move || sweeper(ctx, interval));
    }
    {
        let ctx = ctx.clone();
        thread::spawn(move || syncer(ctx, sync_interval));
    }

    // The unix socket is the same router, so an agent with filesystem access
    // does not need a port at all.
    if !socket_path.is_empty() {
        if let Some(parent) = std::path::Path::new(&socket_path).parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        let _ = std::fs::remove_file(&socket_path);
        match UnixListener::bind(&socket_path) {
            Ok(l) => {
                let h: Handler = {
                    let ctx = ctx.clone();
                    Arc::new(move |req| route(&ctx, req))
                };
                thread::spawn(move || {
                    for conn in l.incoming() {
                        let h = h.clone();
                        if let Ok(mut s) = conn {
                            thread::spawn(move || http::handle_stream(&mut s, &h));
                        }
                    }
                });
                eprintln!("fabric: listening on unix:{socket_path}");
            }
            Err(e) => eprintln!("fabric: unix socket {socket_path}: {e} (continuing on TCP)"),
        }
    }

    let listener = TcpListener::bind(&addr).map_err(|e| format!("bind {addr}: {e}"))?;
    eprintln!(
        "fabric: v{VERSION} on http://{addr} db={} pool={} relay={} board={}",
        ctx.store.db,
        ctx.blocks.pool,
        ctx.relay.url,
        if ctx.board.enabled() { &ctx.board.base } else { "disabled" }
    );
    let h: Handler = {
        let ctx = ctx.clone();
        Arc::new(move |req| route(&ctx, req))
    };
    http::serve_tcp(listener, h).map_err(|e| e.to_string())
}

fn build_ctx() -> Result<Arc<Ctx>, String> {
    let db = std::env::var("FABRIC_DB").unwrap_or_else(|_| "agent_fabric".into());
    let store = Store::new(&db)?;
    let board = DoSync::new(&std::env::var("FABRIC_DO_URL").unwrap_or_default());
    Ok(Arc::new(Ctx {
        store,
        blocks: Blocks::from_env(),
        relay: Relay::from_env(),
        deps: Deps::from_env(),
        board,
        lease_secs: env_u64("FABRIC_LEASE_SECS", 120),
    }))
}

fn main() {
    let cmd = std::env::args().nth(1).unwrap_or_else(|| "serve".into());
    match cmd.as_str() {
        "version" => println!("agent-fabric {VERSION}"),
        "gate" => {
            let ctx = match build_ctx() {
                Ok(c) => c,
                Err(e) => {
                    eprintln!("agent-fabric gate: {e}");
                    std::process::exit(1);
                }
            };
            let (failures, report) = adapters::gate(&ctx.store, &ctx.blocks, &ctx.relay, &ctx.deps);
            println!("{}", serde_json::to_string_pretty(&report).unwrap_or_default());
            if failures.is_empty() {
                println!("gate: all required dependencies answered");
            } else {
                for f in &failures {
                    eprintln!("gate: FAIL {f}");
                }
                std::process::exit(1);
            }
        }
        "capabilities" => {
            let ctx = match build_ctx() {
                Ok(c) => c,
                Err(e) => {
                    eprintln!("agent-fabric capabilities: {e}");
                    std::process::exit(1);
                }
            };
            let (failures, report) = adapters::gate(&ctx.store, &ctx.blocks, &ctx.relay, &ctx.deps);
            println!(
                "{}",
                serde_json::to_string_pretty(&json!({
                    "ok": failures.is_empty(),
                    "failures": failures,
                    "deps": report,
                    "git_mounts": adapters::git_mounts(&ctx.deps.git_mounts),
                    "gpu": adapters::gpu(),
                }))
                .unwrap_or_default()
            );
        }
        "sync" => {
            let ctx = match build_ctx() {
                Ok(c) => c,
                Err(e) => {
                    eprintln!("agent-fabric sync: {e}");
                    std::process::exit(1);
                }
            };
            match sync_once(&ctx) {
                Ok(v) => println!("{}", serde_json::to_string_pretty(&v).unwrap_or_default()),
                Err(e) => {
                    eprintln!("agent-fabric sync: {e}");
                    std::process::exit(1);
                }
            }
        }
        "serve" => match build_ctx() {
            Ok(ctx) => {
                if let Err(e) = serve(ctx) {
                    eprintln!("agent-fabric: {e}");
                    std::process::exit(1);
                }
            }
            Err(e) => {
                eprintln!("agent-fabric: {e}");
                std::process::exit(1);
            }
        },
        other => {
            eprintln!("agent-fabric: unknown command {other:?} (serve|gate|capabilities|sync|version)");
            let _ = std::io::stdout().flush();
            std::process::exit(2);
        }
    }
}
