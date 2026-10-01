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

run().catch((err) => {
  console.error(`ci-checkin failed (ignored): ${err.message}`);
  process.exit(0);
});
