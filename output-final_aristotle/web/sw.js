// kant-zk-pastebin — offline pinning service worker.
//
// Two jobs:
//   1. cache the application shell so the client keeps working offline;
//   2. serve pinned pastes from local storage under /pin/<witness>, so a pinned
//      paste has a real URL that other tabs (and <iframe>/<img> loads) can hit.
//
// Pins are written by index.html into the Cache Storage bucket PIN_CACHE under
// the key "/pin/<witness>". This worker just resolves them; it never mints
// credits itself — the ledger (Kant/Credits.lean) is authoritative and lives in
// the page.

const SHELL_CACHE = "kantzk-shell-v7";
const PIN_CACHE = "kantzk-pins-v1";

// kant-kernel-embedded.mjs is part of the shell, not an optional extra: it is
// the base64 copy of the Lean-extracted kernel that the loader falls back to,
// so caching it is what keeps the proved kernel available offline and on hosts
// that ship only web/.
const SHELL = ["./", "./index.html", "./lab.html", "./kantzk.mjs", "./kant-wasm.mjs",
               "./kant-kernel-embedded.mjs",
               "./kant-net.mjs", "./kant-qr.mjs", "./kant-uucp.mjs",
               "./kant-site.mjs", "./kant-flow.mjs", "./kant.config", "./kant-logo.svg"];

// The standalone kernel binary, cached best-effort from wherever it is served.
const OPTIONAL = ["../dist/kant_kernel.wasm", "./kant_kernel.wasm"];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(SHELL_CACHE)
      .then(async (c) => {
        await c.addAll(SHELL);
        await Promise.all(OPTIONAL.map((u) => c.add(u).catch(() => {})));
      })
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) =>
        Promise.all(
          keys
            .filter((k) => k !== SHELL_CACHE && k !== PIN_CACHE)
            .map((k) => caches.delete(k)),
        )
      )
      .then(() => self.clients.claim()),
  );
});

self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);

  if (url.origin === self.location.origin && url.pathname.includes("/pin/")) {
    const witness = url.pathname.slice(url.pathname.indexOf("/pin/") + 5);
    event.respondWith(servePin(witness));
    return;
  }

  event.respondWith(
    caches.match(event.request).then((hit) =>
      hit ||
      fetch(event.request).then((res) => {
        if (res.ok && event.request.method === "GET") {
          const copy = res.clone();
          caches.open(SHELL_CACHE).then((c) => c.put(event.request, copy));
        }
        return res;
      }).catch(() => new Response("offline and not pinned", { status: 504 }))
    ),
  );
});

async function servePin(witness) {
  const cache = await caches.open(PIN_CACHE);
  const hit = await cache.match("/pin/" + witness);
  if (hit) {
    // Tell the page a serve happened so it can credit the operator.
    const clientList = await self.clients.matchAll();
    for (const client of clientList) {
      client.postMessage({ kind: "served", witness });
    }
    return hit;
  }
  return new Response("no such pin: " + witness, {
    status: 404,
    headers: { "content-type": "text/plain" },
  });
}

// Allow the page to pin/unpin without touching Cache Storage directly.
self.addEventListener("message", (event) => {
  const msg = event.data || {};
  if (msg.kind === "pin") {
    event.waitUntil(
      caches.open(PIN_CACHE).then((c) =>
        c.put(
          "/pin/" + msg.witness,
          new Response(msg.body, {
            headers: { "content-type": msg.contentType || "text/plain; charset=utf-8" },
          }),
        )
      ),
    );
  } else if (msg.kind === "unpin") {
    event.waitUntil(caches.open(PIN_CACHE).then((c) => c.delete("/pin/" + msg.witness)));
  }
});
