// gui2lean4 proof for the kant paste page: recorded browser session that
// (1) joins the vaciu room from an invite link in a real browser,
// (2) captures the a11y/DOM evidence at each step,
// (3) posts a message through the proved wasm kernel,
// (4) mints a new group pass (from the owner invite) for sharing,
// (5) emits the evidence bundle for the Lean4 verification step.
import fs from "node:fs";
import * as N from "../web/kant-net.mjs";
import * as P from "../web/kant-pass.mjs";

const PORT = 9222;
const OUT = "/tmp/gui2lean4-kant";
fs.mkdirSync(OUT, { recursive: true });

const cfg = JSON.parse(fs.readFileSync("/var/lib/kant-zk/rooms/vaciu.json", "utf8"));
const CF = "https://kant-zk-relay.jmikedupont2.workers.dev";
const ownerInv = N.parseInviteUrl(cfg.invite);
const cfInv = { ...ownerInv, relay: CF };
const joinLink = N.inviteUrl("https://kant-zk-pastebin.pages.dev/paste.html", cfInv);

// ---- CDP plumbing ----------------------------------------------------
const targets = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();
const page = targets.find((t) => t.type === "page");
const ws = new WebSocket(page.webSocketDebuggerUrl);
await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
let nextId = 0;
const pending = new Map();
const frames = [];
ws.onmessage = (ev) => {
  const m = JSON.parse(String(ev.data));
  if (m.method === "Page.screencastFrame") {
    frames.push(m.params.data);
    send("Page.screencastFrameAck", { sessionId: m.params.sessionId }).catch(() => {});
    return;
  }
  if (!m.id) return;
  const p = pending.get(m.id);
  if (!p) return;
  pending.delete(m.id);
  m.error ? p.reject(new Error(JSON.stringify(m.error))) : p.resolve(m.result);
};
const send = (method, params = {}) => new Promise((resolve, reject) => {
  const id = ++nextId;
  pending.set(id, { resolve, reject });
  ws.send(JSON.stringify({ id, method, params }));
});
const evalJs = async (expression, opts = {}) => {
  const r = await send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true, ...opts });
  if (r.exceptionDetails) throw new Error("page exception: " + JSON.stringify(r.exceptionDetails).slice(0, 500));
  return r.result.value;
};
const waitFor = async (expr, timeoutMs = 25000) => {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    if (await evalJs(`Boolean(${expr})`)) return true;
    await new Promise((r) => setTimeout(r, 250));
  }
  throw new Error("timeout: " + expr);
};
// a11y evidence: landmark map + interactive names + telemetry values
const a11ySnapshot = () => evalJs(`JSON.stringify({
  url: location.href.split("#")[0],
  landmarks: [...document.querySelectorAll("header, nav, main, section, [role]")].map((el) => ({
    tag: el.tagName.toLowerCase(), role: el.getAttribute("role"), ariaLabel: el.getAttribute("aria-label"),
  })),
  interactive: [...document.querySelectorAll("button, a, input, textarea")].map((el) => ({
    tag: el.tagName.toLowerCase(), id: el.id || null,
    name: (el.getAttribute("aria-label") || el.innerText || el.placeholder || el.title || "").trim().slice(0, 60),
    disabled: !!el.disabled,
  })),
  telemetry: {
    roominfo: document.getElementById("roominfo")?.textContent ?? "",
    passleft: document.getElementById("passleft")?.textContent ?? "",
    log: document.getElementById("log")?.textContent.slice(0, 400) ?? "",
    postEnabled: !document.getElementById("post")?.disabled,
  },
})`);

const evidence = { steps: [] };
const step = async (name) => {
  const snap = JSON.parse(await a11ySnapshot());
  evidence.steps.push({ name, t: new Date().toISOString(), ...snap });
  const shot = await send("Page.captureScreenshot", { format: "png" });
  fs.writeFileSync(`${OUT}/${String(evidence.steps.length).padStart(2, "0")}-${name}.png`,
    Buffer.from(shot.data, "base64"));
  console.log(`[step ${evidence.steps.length}] ${name}: postEnabled=${snap.telemetry.postEnabled} room="${snap.telemetry.roominfo.slice(0, 50)}"`);
};

// ---- recorded browser flow -------------------------------------------
await send("Page.enable");
await send("Runtime.enable");
await send("Network.enable");
await send("Page.startScreencast", { format: "png", everyNthFrame: 1 });

console.log("== join the room from the invite link ==");
await send("Page.navigate", { url: joinLink });
await waitFor(`document.readyState === "complete"`, 15000);
await step("loaded");
await waitFor(`!document.getElementById("post").disabled`, 20000);
await step("auto-joined");

console.log("== post a message through the proved kernel ==");
const text = "gui2lean4 proof: joined from invite link, posting through the proved kernel " + new Date().toISOString();
await evalJs(`document.getElementById("text").focus()`);
await send("Input.insertText", { text });
await step("typed");
const pbtn = await evalJs(`(() => {
  const b = document.getElementById("post");
  b.scrollIntoView({ block: "center" });
  const r = b.getBoundingClientRect();
  return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
})()`);
await send("Input.dispatchMouseEvent", { type: "mouseMoved", x: pbtn.x, y: pbtn.y });
await send("Input.dispatchMouseEvent", { type: "mousePressed", x: pbtn.x, y: pbtn.y, button: "left", buttons: 1, clickCount: 1 });
await send("Input.dispatchMouseEvent", { type: "mouseReleased", x: pbtn.x, y: pbtn.y, button: "left", buttons: 0, clickCount: 1 });
await waitFor(`document.getElementById("log").textContent.includes("posted")`, 25000);
await step("posted");

console.log("== mint a group pass for sharing (owner capability) ==");
const pass = P.mintPass(cfInv, 5);
const shareLink = P.passUrl("https://kant-zk-pastebin.pages.dev/paste.html", pass);
fs.writeFileSync(`${OUT}/share-pass-link.txt`, shareLink);
console.log("share pass (5 posts):", shareLink.slice(0, 100) + "…");

// verify the pass works before sharing (dry-run signature + room check):
const parsed = P.pastePass(P.copyPass(pass));
const sigOk = P.passOk(parsed, cfInv.secret);
const roomOk = P.passRoom(parsed) === N.roomOf(cfInv.secret);
console.log("pass signature valid:", sigOk, "| room matches:", roomOk);

await send("Page.stopScreencast");
fs.writeFileSync(`${OUT}/evidence.json`, JSON.stringify(evidence, null, 2));
fs.writeFileSync(`${OUT}/screencast-frames.json`, JSON.stringify(frames));
console.log(`evidence: ${OUT}/evidence.json, ${frames.length} screencast frames, ${evidence.steps.length} screenshots`);
ws.close();

console.log("SHARE_LINK=" + shareLink);
