// server/test-worker.js — minimal Cloudflare Worker for testing.
//
// This Worker answers /health only. It is the baseline for iterative
// feature deployment: we add thunks, scheduler, DO state, and snapshots
// in subsequent deploys.
//
// Usage:
//   ./deploy-cloudflare-worker.sh test-deploy
//
// Once verified, we promote features to the production relay (worker.js).

const VERSION = "0.0.1";
const NAME = "kant-zk-test";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // Health check — used to verify deployment and version
    if (url.pathname === "/health") {
      return new Response(JSON.stringify({
        ok: true,
        name: NAME,
        version: VERSION,
        platform: "cloudflare-test",
      }), {
        headers: { "content-type": "application/json" },
      });
    }

    return new Response("not found", { status: 404 });
  },
};
