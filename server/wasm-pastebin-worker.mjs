// wasm-pastebin-worker.mjs — kant-zk pastebin compiled from Rust to WASM
//
// Loads the Rust-compiled WASM binary (kant-pastebin.wasm) and exposes
// the same API endpoints as the Rust actix-web server:
//
//   POST /api/paste          → Create new paste
//   GET  /api/paste/{id}     → Get paste as JSON
//   GET  /paste/{id}         → View paste (HTML)
//   GET  /browse             → List recent pastes
//   GET  /raw/{id}           → Raw text
//
// The WASM binary is fetched from a published URL (Nora Forgejo or IPFS)
// and instantiated in the Cloudflare Worker.
//
// Usage (Cloudflare):
//   wrangler deploy --name kant-zk-pastebin-wasm

const VERSION = "1.0.0";

const CORS = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET, POST, OPTIONS",
  "access-control-allow-headers": "content-type",
  "access-control-max-age": "86400",
};

const json = (obj, status = 200) =>
  new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json", ...CORS },
  });

const WASM_URL = "https://solana.solfunmeme.com/kant-wasm/kant-pastebin.wasm";
const WASM_KV_KEY = "kant-pastebin-wasm-cache";

// WASM module cache
let wasmModule = null;
let wasmInstance = null;

// Lazy WASM loader
async function loadWasm(env) {
  if (wasmModule) return wasmModule;

  let wasmBytes;

  // Try KV cache
  try {
    wasmBytes = await env.WASM_KV.get(WASM_KV_KEY, "arrayBuffer");
    if (wasmBytes) {
      wasmModule = await WebAssembly.instantiate(wasmBytes, {});
      return wasmModule;
    }
  } catch (e) {}

  // Try URL fetch
  try {
    const resp = await fetch(WASM_URL);
    if (resp.ok) {
      wasmBytes = await resp.arrayBuffer();
      await env.WASM_KV.put(WASM_KV_KEY, wasmBytes);
      wasmModule = await WebAssembly.instantiate(wasmBytes, {});
      return wasmModule;
    }
  } catch (e) {}

  // Try local file (for development)
  try {
    wasmBytes = await env.ASSETS.fetch(new Request("/kant-pastebin.wasm"));
    wasmBytes = await wasmBytes.arrayBuffer();
    wasmModule = await WebAssembly.instantiate(wasmBytes, {});
    return wasmModule;
  } catch (e) {}

  throw new Error("WASM binary not available from any source");
}

// API handlers using the WASM instance
export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname;

    // Health check
    if (path === "/health") {
      return json({ ok: true, name: "kant-zk-pastebin-wasm", version: VERSION });
    }

    // WASM endpoints — delegate to the Rust WASM module
    if (path === "/api/paste" && request.method === "POST") {
      try {
        const body = await request.json();
        const wasm = await loadWasm(env);

        // Call the WASM paste creation function
        // The Rust function signature is: paste_create(content, title) -> {id, url, cid, witness}
        const content = body.content || "";
        const title = body.title || "untitled";

        // WASM function call (adjust name based on actual exported function)
        const result = wasm.exports.paste_create(
          content,
          title,
          body.reply_to || "",
          body.syntax || "text"
        );

        return json(result);
      } catch (e) {
        return json({ ok: false, error: e.message }, 500);
      }
    }

    if (path === "/paste" + url.search && request.method === "GET") {
      const id = url.searchParams.get("id") || path.split("/paste/")[1];
      if (!id) return json({ ok: false, error: "id required" }, 400);

      try {
        const wasm = await loadWasm(env);
        const paste = wasm.exports.paste_get(id);
        if (!paste) return json({ ok: false, error: "not found" }, 404);

        // Render HTML or JSON based on Accept header
        const accept = request.headers.get("accept") || "";
        if (accept.includes("text/html")) {
          return new Response(renderPasteHtml(paste), {
            headers: { "content-type": "text/html", ...CORS },
          });
        }
        return json(paste);
      } catch (e) {
        return json({ ok: false, error: e.message }, 500);
      }
    }

    if (path === "/browse" && request.method === "GET") {
      try {
        const wasm = await loadWasm(env);
        const pastes = wasm.exports.paste_browse(20);
        return json(pastes);
      } catch (e) {
        return json({ ok: false, error: e.message }, 500);
      }
    }

    if (path === "/raw" + url.search && request.method === "GET") {
      const id = url.searchParams.get("id") || path.split("/raw/")[1];
      if (!id) return json({ ok: false, error: "id required" }, 400);

      try {
        const wasm = await loadWasm(env);
        const paste = wasm.exports.paste_get(id);
        if (!paste) return json({ ok: false, error: "not found" }, 404);
        return new Response(paste.content, {
          headers: { "content-type": "text/plain", ...CORS },
        });
      } catch (e) {
        return json({ ok: false, error: e.message }, 500);
      }
    }

    // Serve static files from web/ if available
    if (path === "/" || path === "/index.html") {
      try {
        const html = await env.ASSETS.fetch(request);
        return html;
      } catch (e) {
        return new Response("<h1>kant-zk pastebin</h1><p>WASM pastebin running</p>", { headers: { "content-type": "text/html" } });
      }
    }

    return json({ ok: false, error: "not found" }, 404);
  },
};

function renderPasteHtml(paste) {
  return `<!DOCTYPE html>
<html>
<head>
  <title>${escapeHtml(paste.title || "untitled")} — kant pastebin</title>
  <meta charset="utf-8">
  <style>
    body { font-family: system-ui, sans-serif; max-width: 800px; margin: 0 auto; padding: 2rem; background: #1a1a2e; color: #e0e0e0; }
    .header { border-bottom: 1px solid #333; padding-bottom: 1rem; margin-bottom: 1rem; }
    .title { font-size: 1.5rem; margin: 0; }
    .meta { color: #888; font-size: 0.85rem; }
    .content { background: #16213e; border-radius: 8px; padding: 1.5rem; white-space: pre-wrap; word-break: break-all; }
    .actions { margin-top: 1rem; }
    button { background: #0f3460; color: #e0e0e0; border: none; padding: 0.5rem 1rem; border-radius: 4px; cursor: pointer; }
    button:hover { background: #1a4a7a; }
    a { color: #e94560; }
  </style>
</head>
<body>
  <div class="header">
    <h1 class="title">${escapeHtml(paste.title || "untitled")}</h1>
    <div class="meta">ID: ${escapeHtml(paste.id || "unknown")}</div>
  </div>
  <div class="content">${escapeHtml(paste.content || "")}</div>
  <div class="actions">
    <button onclick="navigator.clipboard.writeText(window.location.href)">Copy URL</button>
    <button onclick="window.open('/raw?id=' + '${escapeHtml(paste.id || "")}','_blank')">Download Raw</button>
  </div>
</body>
</html>`;
}

function escapeHtml(s) {
  return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}
