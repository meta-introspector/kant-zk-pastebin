// Repro: creator tab doesn't see joiner's messages; joiner sees creator's.
import { KantNode } from "../web/kant-net.mjs";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const port = 9899;
const relay = spawn("node", ["server/relay.mjs", "--port", String(port)], { cwd: root });
await new Promise(r => setTimeout(r, 700));
const base = `http://127.0.0.1:${port}`;

// Tab A: creator — same wiring as btn-open: newNode, createRoom(effectiveRelay), attach()
const A = new KantNode({ peer: "tabA", log: null, onChange: () => {} });
A.createRoom(base);
A.connect({ bus: false });           // normal tab: bus on, but we can't have BroadcastChannel here
A.startPolling({ wait: 1 });

// Tab B: joiner — joinFrom(): newNode, joinInvite, attach()
const inviteText = A.inviteText();
await new Promise(r => setTimeout(r, 300));
const B = new KantNode({ peer: "tabB", log: null, onChange: () => {} });
B.joinInvite(inviteText);
B.connect({ bus: false });
B.startPolling({ wait: 1 });

await new Promise(r => setTimeout(r, 500));
await B.say("hello from joiner");
await new Promise(r => setTimeout(r, 1500));
console.log("A view:", JSON.stringify(A.view().map(m => m.body && Buffer.from(m.body).toString())));
await A.say("hello from creator");
await new Promise(r => setTimeout(r, 1500));
console.log("B view:", JSON.stringify(B.view().map(m => m.body && Buffer.from(m.body).toString())));
A.stop(); B.stop(); relay.kill();
process.exit(0);
