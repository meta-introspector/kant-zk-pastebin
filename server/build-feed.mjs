// build-feed worker — build results, gated one way and watchable the other.
//
// Two privileges, deliberately not the same one:
//
//   subscribe  — anyone. A room asks to watch the build feed by POSTing its
//                room id. No credential, because watching costs nothing and
//                requires nothing.
//   publish    — CI only. A build result arrives with a bearer token held in
//                Worker secrets, and only then is anything sent to Slack or
//                appended to a room.
//
// The Slack webhook never leaves this Worker: it is a secret binding, read
// here, used here. It is never written into a room line, never returned to a
// client, and never travels over the p2p layer, which is unauthenticated and
// would make a pasted hook readable by every peer and permanent in their logs.
// The idea of users pasting hooks into rooms to subscribe was rejected for
// exactly that reason; subscribing here needs no hook at all.
//
// Rooms live in the relay twins, not here, so publishing hands the line to the
// relay over the same text/plain protocol the page client uses. This worker
// keeps no room state of its own — only the subscriber list, which is small
// and rebuilt by whoever cares. No Durable Object: nothing here is worth a
// billed replica, and PB-19 showed what holding one open costs.
//
// Noise policy: a failure is always announced. A success is announced only for
// workflows that deploy, publish or release, because "the build passed"
// matters when it shipped something and is noise otherwise.

const CORS = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "POST, GET, OPTIONS",
  "access-control-allow-headers": "content-type, authorization",
};

const DEPLOY_WORKFLOWS = /deploy|pages|release|publish/i;
const MAX_SUBSCRIBERS = 256;

const SUBSCRIBERS = new Set();

const json = (obj, status = 200) =>
  new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json", ...CORS },
  });

/** Length-safe comparison, so a wrong token cannot be probed byte by byte. */
function tokenOk(given, expected) {
  if (!given || !expected) return false;
  const a = given.trim(), b = expected.trim();
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/** Should this result be announced? */
function wanted({ conclusion, workflow }) {
  if (conclusion === "success") return DEPLOY_WORKFLOWS.test(workflow ?? "");
  if (conclusion === "skipped") return false;
  // failure, cancelled, timed_out, and anything unrecognised: say something
  // rather than swallow a red build.
  return true;
}

const ICON = {
  success: ":white_check_mark:",
  failure: ":x:",
  cancelled: ":no_entry_sign:",
  timed_out: ":hourglass:",
  skipped: ":next_track_button:",
};

/** One line in Slack's markdown, and posted to rooms verbatim. */
function render(b) {
  const icon = ICON[b.conclusion] ?? ":grey_question:";
  const verb = b.conclusion === "success" ? "built" : b.conclusion;
  const where = b.url ? ` — <${b.url}|run>` : "";
  return `${icon} *${b.repo ?? "kant"}* · ${b.workflow}${verb === "built" ? "" : " " + verb}` +
    (b.branch ? ` (\`${b.branch}\`)` : "") + where;
}

async function toSlack(env, line) {
  if (!env.SLACK_WEBHOOK) return { ok: false, why: "SLACK_WEBHOOK secret is not set" };
  try {
    const r = await fetch(env.SLACK_WEBHOOK, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ text: line }),
    });
    return { ok: r.ok, status: r.status, body: (await r.text()).slice(0, 200) };
  } catch (e) {
    return { ok: false, why: String(e?.message ?? e) };
  }
}

/** Hand the line to the relay, which owns the room. */
async function toRooms(env, room, line) {
  const base = (env.RELAY_BASE ?? "").replace(/\/+$/, "");
  if (!base) return { ok: false, why: "RELAY_BASE is not configured" };
  try {
    const r = await fetch(`${base}/room/${encodeURIComponent(room)}`, {
      method: "POST",
      headers: { "content-type": "text/plain" },
      body: line,
    });
    return { ok: r.ok, status: r.status };
  } catch (e) {
    return { ok: false, why: String(e?.message ?? e) };
  }
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });

    if (url.pathname === "/health") {
      return json({
        ok: true,
        name: "kant-build-feed",
        subscribers: SUBSCRIBERS.size,
        relay: env.RELAY_BASE ?? null,
        slack: env.SLACK_WEBHOOK ? "configured" : "not configured",
        publishGated: Boolean(env.PUBLISH_TOKEN),
      });
    }

    // ---- open: watch the feed ----
    if (url.pathname === "/subscribe" && request.method === "POST") {
      const { room } = await request.json().catch(() => ({}));
      if (!room || typeof room !== "string" || room.length > 128) {
        return json({ ok: false, error: "room required" }, 400);
      }
      if (!SUBSCRIBERS.has(room) && SUBSCRIBERS.size >= MAX_SUBSCRIBERS) {
        return json({ ok: false, error: "subscriber limit reached" }, 503);
      }
      SUBSCRIBERS.add(room);
      return json({ ok: true, subscribed: room, subscribers: SUBSCRIBERS.size });
    }

    if (url.pathname === "/unsubscribe" && request.method === "POST") {
      const { room } = await request.json().catch(() => ({}));
      return json({ ok: true, removed: SUBSCRIBERS.delete(room), subscribers: SUBSCRIBERS.size });
    }

    if (url.pathname === "/subscribers" && request.method === "GET") {
      return json({ ok: true, subscribers: [...SUBSCRIBERS] });
    }

    // ---- gated: CI only ----
    if (url.pathname === "/publish" && request.method === "POST") {
      const given = (request.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
      if (!tokenOk(given, env.PUBLISH_TOKEN)) {
        // Say nothing about which half was wrong.
        return json({ ok: false, error: "unauthorized" }, 401);
      }
      const body = await request.json().catch(() => ({}));
      if (!body?.workflow || !body?.conclusion) {
        return json({ ok: false, error: "workflow and conclusion required" }, 400);
      }
      const line = render(body);
      if (!wanted(body)) {
        // 200: the run happened, we are choosing not to announce it.
        return json({ ok: true, announced: false, why: `success of a non-deploy workflow`, line });
      }
      const slack = await toSlack(env, line);
      const rooms = [];
      for (const room of SUBSCRIBERS) rooms.push({ room, ...(await toRooms(env, room, line)) });
      return json({ ok: true, announced: true, line, slack, rooms });
    }

    return json({ ok: false, error: "not found" }, 404);
  },
};