// pastebin-test.mjs — checks for the pastebin carrier layer.
//
// Three kinds of check:
//   1. pure: URL parsing, chunking, QR rendering (no network);
//   2. spool: a temp spool directory in the shape of the live one
//      (index.jsonl, .txt pastes, .cid aliases) — read, resolve, take;
//   3. api: the live service at solana.solfunmeme.com, when it answers
//      (skipped, not failed, when it does not).
//
// Run:  node web/pastebin-test.mjs

import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  joinUrl, parsePasteUrl, isPasteUrl, pasteApi, pasteSpool, unwrapPaste,
} from "./kant-pastebin.mjs";
import { pastebinChannel, qrChannel, channels, chunksFor } from "./kant-share.mjs";

let checks = 0;
const check = (name, fn) => { fn(); checks += 1; console.log(`  ok  ${name}`); };
const checkAsync = async (name, fn) => { await fn(); checks += 1; console.log(`  ok  ${name}`); };

// ------------------------------------------------------------------ pure

check("joinUrl joins without doubling slashes", () => {
  assert.equal(joinUrl("https://h/x/", "/paste/1"), "https://h/x/paste/1");
  assert.equal(joinUrl("https://h", "paste/1"), "https://h/paste/1");
});

check("parsePasteUrl reads paste, raw and bare ids", () => {
  assert.deepEqual(
    parsePasteUrl("https://solana.solfunmeme.com/pastebin/paste/abc_1"),
    { backend: "https://solana.solfunmeme.com/pastebin", id: "abc_1", raw: false });
  assert.equal(
    parsePasteUrl("https://h/pastebin/raw/bafk1234").raw, true);
  assert.equal(
    parsePasteUrl("https://h/pastebin/paste/x").id, "x");
  assert.equal(parsePasteUrl("not a url at all"), null);
  assert.ok(isPasteUrl("https://h/pastebin/paste/x"));
  assert.ok(!isPasteUrl("hello world"));
});

check("chunksFor splits to the carrier capacity", () => {
  assert.deepEqual(chunksFor("hello", "tweet"), ["hello"]);
  const parts = chunksFor("x".repeat(700), "tweet");
  assert.equal(parts.length, 3);
  assert.equal(parts[0].length, 280);
  assert.throws(() => chunksFor("x", "nope"), /no such carrier/);
});

check("qrChannel renders an SVG QR of the text", () => {
  const svg = qrChannel().share("https://kant.example/#deadbeef");
  assert.ok(svg.startsWith("<svg"));
  assert.ok(svg.includes("<rect")); // modules drawn as crisp rects
  assert.throws(() => qrChannel().share("x".repeat(4000)), /2953/);
});

check("unwrapPaste strips the server's wrappers", () => {
  const raw = "the text\n\n&lt;div typeof=\"erdfa:SheafSection dasl:Type5\" about=\"#x\">\n" +
    "  &lt;meta property=\"erdfa:shard\" content=\"33,51,23\" />\n&lt;/div>";
  assert.equal(unwrapPaste(raw), "the text");
  const stored = "--- 20260910_000001_x ---\nTitle: \"x\"\nCID: bafk1\nWitness: w\n\nthe text\n";
  assert.equal(unwrapPaste(stored), "the text");
  assert.equal(unwrapPaste("just text"), "just text");
});

// ----------------------------------------------------------------- spool

// A spool in the shape of the live one: index.jsonl, .txt pastes,
// .cid alias files (the server's dedup path), newest last in the index.
const SPOOL = mkdtempSync(join(tmpdir(), "kant-spool-"));
const paste = (n, id, text, extra = {}) => {
  writeFileSync(join(SPOOL, `${id}.txt`), text);
  const e = { id, title: id, timestamp: `20260910_00000${n}`, filename: `${id}.txt`,
    uucp_path: join(SPOOL, `${id}.txt`), ...extra };
  writeFileSync(join(SPOOL, "index.jsonl"), `${JSON.stringify(e)}\n`, { flag: "a" });
  return e;
};

const E1 = paste(1, "paste_one", "first paste");
const E2 = paste(2, "paste_two", "https://kant.example/#invite:here");
const E3 = paste(3, "paste_three", "noise");
writeFileSync(join(SPOOL, "bafkdead.cid"), "paste_two\n"); // CID alias -> paste_two

check("spool.list walks the index newest first", () => {
  const ids = pasteSpool(SPOOL).list().map((e) => e.id);
  assert.deepEqual(ids, ["paste_three", "paste_two", "paste_one"]);
});

check("spool.read reads by slug id", () => {
  assert.equal(pasteSpool(SPOOL).read("paste_one"), "first paste");
});

check("spool.read resolves .cid aliases (CID permalinks)", () => {
  assert.equal(pasteSpool(SPOOL).read("bafkdead"), "https://kant.example/#invite:here");
  assert.equal(pasteSpool(SPOOL).resolve("bafkdead"), "paste_two");
  assert.equal(pasteSpool(SPOOL).read("no-such-paste"), null);
});

check("spool.take walks newest first until takeFn accepts", () => {
  const spool = pasteSpool(SPOOL);
  const got = spool.take((text) => (text.includes("#invite") ? text.toUpperCase() : null));
  assert.equal(got.value, "HTTPS://KANT.EXAMPLE/#INVITE:HERE");
  assert.equal(got.entry.id, "paste_two");
  assert.equal(got.tried, 2);
  assert.equal(spool.take(() => null), null);
});

check("spool.list honours since and limit", () => {
  const spool = pasteSpool(SPOOL);
  assert.deepEqual(spool.list({ limit: 1 }).map((e) => e.id), ["paste_three"]);
  assert.deepEqual(
    spool.list({ since: "20260910_000002" }).map((e) => e.id),
    ["paste_three", "paste_two"]);
});

// ------------------------------------------------- pastebinChannel (spool)

check("pastebinChannel.take walks the spool with no argument", async () => {
  const ch = pastebinChannel("https://solana.solfunmeme.com/pastebin", SPOOL,
    { takeFn: (t) => (t.includes("#invite") ? t : null) });
  assert.equal(await ch.take(), "https://kant.example/#invite:here");
});

check("pastebinChannel.take reads a paste URL off the spool", async () => {
  const ch = pastebinChannel("https://solana.solfunmeme.com/pastebin", SPOOL);
  // the URL names the backend host, so the spool answers before the net
  assert.equal(
    await ch.take("https://solana.solfunmeme.com/pastebin/paste/paste_one"),
    "first paste");
});

check("unwired channels say so instead of pretending", () => {
  const all = channels({ backend: "https://x", spoolDir: SPOOL });
  assert.equal(all.pastebin.name, "pastebin");
  assert.equal(all.qr.name, "qr");
  for (const name of ["tweet", "discord", "telegram", "facebook", "gist"]) {
    assert.ok(all[name].unired ?? all[name].unwired, `${name} should be marked unwired`);
    assert.throws(() => all[name].share("x"), /wired/);
    assert.equal(all[name].take(), null);
  }
});

// ------------------------------------------------------------------- api
// Live checks: the real service, when it answers.

const BACKEND = "https://solana.solfunmeme.com/pastebin";
const live = await pasteApi(BACKEND).health();

if (live) {
  console.log("live service up — checking api round trip");
  const api = pasteApi(BACKEND);
  const text = `kant-pastebin.mjs check ${new Date().toISOString()}`;

  await checkAsync("api.put posts and returns a paste record", async () => {
    const res = await api.put(text, { title: "kant-pastebin.mjs check" });
    assert.ok(res.id);
    assert.ok(res.cid.startsWith("bafk"));
    assert.ok(res.witness.length >= 32);
    assert.ok(/https?:\/\//.test(res.url));
  });

  await checkAsync("api.get reads the text back by id and URL", async () => {
    const res = await api.put(text, { title: "kant-pastebin.mjs check" });
    assert.equal(await api.get(res.id), text);
    assert.equal(await api.get(res.url), text);
    assert.equal(await api.get(res.permalink), text); // the CID permalink
  });

  await checkAsync("api.search finds the paste", async () => {
    const res = await api.put(text, { title: "kant-pastebin.mjs check" });
    // search for the paste's title phrase; the server content-dedupes, so
    // the id may alias an older paste of the same content
    const found = await api.search("kant-pastebin.mjs check", { limit: 20 });
    assert.ok(found.some((r) => r.id === res.id), `search did not find ${res.id}`);
  });
} else {
  console.log("live service not answering — api checks skipped");
}

console.log(`\n${checks} check(s) passed`);
