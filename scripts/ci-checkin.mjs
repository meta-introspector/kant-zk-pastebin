#!/usr/bin/env node
// ci-checkin.mjs — one stateless check-in post to a Kant room.
//
// Built for CI: every agent that runs the build checks in with us in the
// chat, saying what it built and whether it is green.  State-free by
// design — no state file to race on between concurrent jobs:
//
//   KANT_CI_RELAY  the relay base URL            (required)
//   KANT_CI_SECRET hex of the room secret        (required)
//   KANT_CI_NAME   sender id, e.g. gh-runner     (default ci-agent)
//   MSG (or argv)  the check-in text
//
// When KANT_FLEET_RELAY is also set, a machine-readable build record is
// additionally posted as a plain JSON line to KANT_FLEET_ROOM (default
// twitterstorm-fleet-builds) — the same named-room protocol the tracker
// fleet mesh (scripts/peer-relay-discovery.ts) already speaks, so sinks
// can record builds into sqlite and mesh-sync them.  Never put secrets
// in the record: the room is public and append-only.
//
// Fail-soft on purpose: a chat outage must never fail a build.  The only
// hard errors are missing configuration (exit 2 before anything is sent).
//
//   MSG="build 123 green" KANT_CI_RELAY=https://… KANT_CI_SECRET=abcd… \
//     node scripts/ci-checkin.mjs

import * as C from "../web/kant-cli.mjs";
import { hexDecode } from "../web/kantzk.mjs";

const relay = (process.env.KANT_CI_RELAY ?? "").replace(/\/+$/, "");
const secretHex = process.env.KANT_CI_SECRET ?? "";
const self = process.env.KANT_CI_NAME ?? "ci-agent";
const text = process.env.MSG ?? process.argv.slice(2).join(" ");

if (!relay || !secretHex || !text) {
  console.error("ci-checkin: need KANT_CI_RELAY, KANT_CI_SECRET and MSG");
  process.exit(2);
}

const client = {
  self,
  relay,
  secret: hexDecode(secretHex.trim()),
  seq: 0,
  cursor: 0,
  lines: [],
};

const line = C.printMsg(C.compose(client, text));
const req = C.postLine(client, line);

const run = async () => {
  const res = await fetch(req.url, {
    method: "POST",
    headers: { "content-type": "text/plain" },
    body: req.body,
  });
  if (!res.ok) throw new Error(`relay ${res.status}`);
  const answer = await res.json().catch(() => ({}));
  console.log(`checked in at cursor ${answer.cursor ?? "?"} in room ${C.clientRoom(client)}`);
};

// The machine-readable record for the fleet room (plain JSON, named room,
// no kz envelope — matches what PeerRelayClient.discover() parses).  No
// credential-shaped keys, ever (docs/SECRET-HAZARDS.md rule: the room is
// public and append-only).
async function fleetPost() {
  const fleetRelay = (process.env.KANT_FLEET_RELAY ?? "").replace(/\/+$/, "");
  if (!fleetRelay) return;
  const room = process.env.KANT_FLEET_ROOM ?? "twitterstorm-fleet-builds";
  const record = {
    kind: "build",
    repo: process.env.KANT_BUILD_REPO ?? "",
    workflow: process.env.KANT_BUILD_WORKFLOW ?? "",
    status: process.env.KANT_BUILD_STATUS ?? "",
    runId: process.env.KANT_BUILD_RUN_ID ?? self,
    commit: (process.env.KANT_BUILD_COMMIT ?? "").slice(0, 120),
    url: process.env.KANT_BUILD_URL ?? "",
    at: Date.now(),
    sender: self,
  };
  try {
    const res = await fetch(`${fleetRelay}/room/${encodeURIComponent(room)}`, {
      method: "POST",
      headers: { "content-type": "text/plain" },
      body: `${JSON.stringify(record)}\n`,
    });
    if (!res.ok) throw new Error(`fleet relay ${res.status}`);
    const answer = await res.json().catch(() => ({}));
    console.log(`fleet record posted to ${room} (cursor ${answer.cursor ?? "?"})`);
  } catch (err) {
    console.error(`fleet post failed (ignored): ${err.message}`);
  }
}

// Chat line first, then the fleet record — each guarded, neither can
// prevent the other, and the process always exits 0.
try {
  await run();
} catch (err) {
  console.error(`ci-checkin failed (ignored): ${err.message}`);
}
await fleetPost();
