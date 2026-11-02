// The durable half of the agent fabric: one Durable Object per board, holding
// the same ordered event lines the local fabric writes to postgres.
//
// It is deliberately dumb. It does not parse tasks, move states, or trust
// anything: it appends lines and hands them back in order, so a Worker or a
// second machine can read the board and a restarted fabric can rebuild its
// postgres from it. Every line carries its own `block_cid`, and the fabric
// recomputes it on the way back in, so this object cannot forge an event even
// though it is the one holding the bytes.
//
//   GET  /health            -> { ok, service, cursor, lines }
//   POST /append  {lines}   -> { ok, cursor, accepted, skipped }
//   GET  /since?cursor=N    -> { ok, cursor, lines, truncated }
//   GET  /all               -> { ok, cursor, lines }
//
// Deduplication is by the event's content address, so replaying the same
// batch over a flaky connection changes nothing.

const MAX_LINES = 4096;

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });

export class TaskBoard {
  constructor(state) {
    this.state = state;
    this.storage = state.storage;
  }

  async order() {
    return (await this.storage.get("order")) ?? [];
  }

  async fetch(request) {
    const url = new URL(request.url);
    const path = url.pathname.replace(/^\/board/, "") || "/";

    if (path === "/health") {
      const order = await this.order();
      return json({ ok: true, service: "agent-fabric-board", cursor: order.length, lines: order.length });
    }

    if (path === "/append" && request.method === "POST") {
      let payload;
      try {
        payload = await request.json();
      } catch (e) {
        return json({ ok: false, error: `body is not json: ${e.message}` }, 400);
      }
      const lines = Array.isArray(payload?.lines) ? payload.lines : null;
      if (!lines) return json({ ok: false, error: "lines must be an array" }, 400);

      const order = await this.order();
      const seen = new Set(order);
      let accepted = 0;
      let skipped = 0;
      for (const raw of lines) {
        const text = typeof raw === "string" ? raw : JSON.stringify(raw);
        let cid;
        try {
          cid = JSON.parse(text).block_cid;
        } catch {
          return json({ ok: false, error: "line is not a JSON object" }, 400);
        }
        if (typeof cid !== "string" || !cid.startsWith("b")) {
          return json({ ok: false, error: "line has no block_cid" }, 400);
        }
        if (seen.has(cid)) {
          skipped += 1;
          continue;
        }
        await this.storage.put(`line:${cid}`, text);
        order.push(cid);
        seen.add(cid);
        accepted += 1;
      }
      // Bounded like the relay: keep the most recent MAX_LINES and say so.
      let truncated = false;
      while (order.length > MAX_LINES) {
        const drop = order.shift();
        await this.storage.delete(`line:${drop}`);
        truncated = true;
      }
      await this.storage.put("order", order);
      return json({ ok: true, cursor: order.length, accepted, skipped, truncated });
    }

    if (path === "/since") {
      const cursor = Number(url.searchParams.get("cursor") ?? "0");
      const order = await this.order();
      if (!Number.isFinite(cursor) || cursor < 0) {
        return json({ ok: false, error: "cursor must be a non-negative integer" }, 400);
      }
      const start = Math.min(cursor, order.length);
      const wanted = order.slice(start);
      const lines = [];
      for (const cid of wanted) {
        const text = await this.storage.get(`line:${cid}`);
        if (typeof text === "string") lines.push(text);
      }
      return json({ ok: true, cursor: order.length, lines, truncated: cursor > order.length });
    }

    if (path === "/all") {
      const order = await this.order();
      const lines = [];
      for (const cid of order) {
        const text = await this.storage.get(`line:${cid}`);
        if (typeof text === "string") lines.push(text);
      }
      return json({ ok: true, cursor: order.length, lines });
    }

    return json({ ok: false, error: `no route ${request.method} ${url.pathname}` }, 404);
  }
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === "/health" && !url.pathname.startsWith("/board")) {
      return json({ ok: true, service: "agent-fabric-board", board: "fabric" });
    }
    const id = env.BOARD.idFromName("fabric");
    return env.BOARD.get(id).fetch(request);
  },
};
