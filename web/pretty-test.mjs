// Tests for the profile tag (kzprof) and the formatting module (kant-pretty).
//
// Two claims worth being suspicious about, both tested here:
//   * a profile is self-certifying, so a name nobody can forge is a name whose
//     witness actually covers every field it shows;
//   * formatting is safe, so nothing a peer posts can become markup.
//
//   node web/pretty-test.mjs

import assert from "node:assert/strict";
import * as N from "./kant-net.mjs";
import * as P from "./kant-pretty.mjs";
import { envelopeDecode, envelopeEncode, asciiBytes } from "./kantzk.mjs";

let pass = 0, fail = 0;
const t = async (name, fn) => {
  try { await fn(); console.log(`  ok    ${name}`); pass++; }
  catch (e) { console.log(`  FAIL  ${name}\n        ${e.message}`); fail++; }
};

const ROOM = "room-abc", SENDER = "a".repeat(64), OTHER = "b".repeat(64);
const WIT = "c".repeat(64);

console.log("the profile tag");

await t("a profile round-trips", () => {
  const p = N.profile(ROOM, SENDER, 3, "ada", { bio: "maths", at: 1700000000000 });
  const back = N.parseProf(N.printProf(p));
  assert.deepEqual(back, p);
});

await t("an avatar witness round-trips", () => {
  const p = N.profile(ROOM, SENDER, 4, "ada", { avatar: WIT, at: 1700000000000 });
  assert.equal(N.parseProf(N.printProf(p)).avatar, WIT);
});

await t("a profile with no avatar reads as no avatar", () => {
  const p = N.profile(ROOM, SENDER, 5, "ada", { avatar: "", at: 1 });
  assert.equal(N.parseProf(N.printProf(p)).avatar, "");
});

await t("a name edited on the wire is refused", () => {
  const line = N.printProf(N.profile(ROOM, SENDER, 6, "ada", { at: 1 }));
  // Reprint the envelope with a different name field but the same witness.
  const e = envelopeDecode(line);
  e.fields[3] = asciiBytes("grace");
  assert.equal(N.parseProf(envelopeEncode(e)), null, "a profile whose name changed still verified");
});

await t("a bio edited on the wire is refused", () => {
  const line = N.printProf(N.profile(ROOM, SENDER, 7, "ada", { bio: "a", at: 1 }));
  // Reprint the envelope with a different bio field but the same witness.
  const e = envelopeDecode(line);
  e.fields[4] = asciiBytes("b");
  assert.equal(N.parseProf(envelopeEncode(e)), null, "an edited bio still verified");
});

await t("an avatar swapped for another witness is refused", () => {
  const line = N.printProf(N.profile(ROOM, SENDER, 8, "ada", { avatar: WIT, at: 1 }));
  const e = envelopeDecode(line);
  e.fields[5] = asciiBytes("d".repeat(64));
  assert.equal(N.parseProf(envelopeEncode(e)), null, "an edited avatar still verified");
});

await t("a profile re-tagged as chat is refused", () => {
  // kzchat is five fields and kzprof is eight: a profile cannot be read as
  // chat, and a chat line cannot be read as a profile.
  const line = N.printProf(N.profile(ROOM, SENDER, 9, "ada", { at: 1 }));
  assert.equal(N.parseMsg(line), null);
  const chat = N.printMsg(N.message(ROOM, SENDER, 10, "hello"));
  assert.equal(N.parseProf(chat), null);
});

await t("a profile with no name is refused", () => {
  assert.equal(N.parseProf(N.printProf(N.profile(ROOM, SENDER, 11, "", { at: 1 }))), null);
});

await t("an over-long name is refused", () => {
  const long = "n".repeat(N.PROF_LIMITS.name + 1);
  assert.equal(N.parseProf(N.printProf(N.profile(ROOM, SENDER, 12, long, { at: 1 }))), null);
});

await t("an over-long bio is refused", () => {
  const long = "b".repeat(N.PROF_LIMITS.bio + 1);
  assert.equal(N.parseProf(N.printProf(N.profile(ROOM, SENDER, 13, "ada", { bio: long, at: 1 }))), null);
});

await t("an avatar that is not a witness is refused", () => {
  for (const bad of ["https://example.com/me.png", "javascript:alert(1)", "nothex", "../x"]) {
    assert.equal(N.isWitness(bad), false, `${bad} was accepted as an avatar`);
    const line = N.printProf(N.profile(ROOM, SENDER, 14, "ada", { avatar: bad, at: 1 }));
    assert.equal(N.parseProf(line), null, `an avatar of ${bad} was accepted`);
  }
});

await t("a valid witness is the only avatar shape accepted", () => {
  assert.equal(N.isWitness(WIT), true);
  assert.equal(N.isWitness(WIT.toUpperCase()), false, "witnesses are lower case");
  assert.equal(N.isWitness(`${WIT}0`), false, "65 hex is not a witness");
});

console.log("profiles on a node");

const node = () => new N.KantNode({ peer: SENDER, room: ROOM });

await t("a published profile is found by its peer", async () => {
  const n = node();
  await n.setProfile("ada");
  assert.equal(n.profileOf(SENDER)?.name, "ada");
  assert.equal(n.displayName(SENDER), "ada");
});

await t("a peer with no profile falls back to the short ref", () => {
  const n = node();
  // Not blank, and not 64 hex characters: most peers have never posted a
  // profile, and printing the whole witness is what the UI did before.
  assert.match(n.displayName(OTHER), /^[0-9a-f]{8}$/);
});

await t("the freshest profile per sender wins", () => {
  const n = node();
  n.ingest(N.printProf(N.profile(ROOM, OTHER, 1, "first", { at: 1 })));
  n.ingest(N.printProf(N.profile(ROOM, OTHER, 2, "second", { at: 2 })));
  assert.equal(n.profileOf(OTHER).name, "second");
});

await t("an older profile does not overwrite a newer one", () => {
  const n = node();
  n.ingest(N.printProf(N.profile(ROOM, OTHER, 5, "newer", { at: 5 })));
  n.ingest(N.printProf(N.profile(ROOM, OTHER, 2, "older", { at: 2 })));
  assert.equal(n.profileOf(OTHER).name, "newer", "a replayed old profile won");
});

await t("a profile for another room is ignored", () => {
  const n = node();
  n.ingest(N.printProf(N.profile("other-room", OTHER, 1, "elsewhere", { at: 1 })));
  assert.equal(n.profileOf(OTHER), null);
});

await t("a name is a claim, not an identity", () => {
  // Two peers may both call themselves `ada`; the witness is what tells them
  // apart, which is why displayName never returns the name alone.
  const n = node();
  n.ingest(N.printProf(N.profile(ROOM, SENDER, 1, "ada", { at: 1 })));
  n.ingest(N.printProf(N.profile(ROOM, OTHER, 1, "ada", { at: 1 })));
  assert.equal(n.displayName(SENDER), n.displayName(OTHER));
  assert.notEqual(n.profileOf(SENDER).sender, n.profileOf(OTHER).sender);
});

console.log("escaping");

await t("body text cannot become markup", () => {
  const html = P.renderBody("<script>alert(1)</script>");
  assert.ok(!html.includes("<script>"), html);
  assert.ok(html.includes("&lt;script&gt;"), html);
});

await t("quotes and angle brackets in an attribute are escaped", () => {
  const html = P.avatarHtml({ name: '" onerror="alert(1)', ref: "abcd1234" });
  // The name IS shown, as inert text: the point is that the quotes cannot
  // terminate the attribute. Un-escaping first and then looking for `onerror=`
  // finds the name's own text and reports a break-out that is not there.
  assert.ok(html.includes("&quot;"), html);
  assert.ok(!html.includes('" onerror="'), `the attribute was broken out of: ${html}`);
});

await t("an SVG data URI avatar is refused", () => {
  // image/svg+xml can script. The mime is re-checked at render even though it
  // was checked when the profile was accepted.
  const svg = "data:image/svg+xml;base64,PHN2Zy8+";
  const html = P.avatarHtml({ dataUri: svg, name: "x", ref: "abcd1234" });
  assert.ok(html.includes("initial"), `an SVG avatar was rendered: ${html}`);
});

await t("a png data URI avatar is rendered", () => {
  const png = "data:image/png;base64,iVBORw0KGgo=";
  assert.ok(P.avatarHtml({ dataUri: png, name: "x", ref: "abcd1234" }).includes("<img"));
});

await t("the fallback avatar is an initial", () => {
  assert.ok(P.avatarHtml({ name: "ada", ref: "abcd1234" }).includes(">A<"));
  assert.ok(P.avatarHtml({ name: "", ref: "abcd1234" }).includes(">A<"), "should fall back to the ref");
});

console.log("code and markdown");

await t("a fenced block renders as code", () => {
  const html = P.renderBody("before ```const x = 1 < 2;``` after");
  assert.ok(html.includes('<code class="kcode">const x = 1 &lt; 2;</code>'), html);
  assert.ok(html.includes("before ") && html.includes(" after"), html);
});

await t("inline code renders as code", () => {
  const html = P.renderBody("run `npm test` now");
  assert.ok(html.includes('<code class="kcode">npm test</code>'), html);
});

await t("an unterminated fence still renders as code", () => {
  const html = P.renderBody("```never closed");
  assert.ok(html.includes('<code class="kcode">never closed</code>'), html);
  assert.ok(!html.includes("```"), html);
});

await t("markdown inside code is not interpreted", () => {
  const html = P.renderBody("```**not bold** [not a link](x)```");
  assert.ok(html.includes("**not bold**"), html);
  assert.ok(!html.includes("<strong>"), html);
  assert.ok(!html.includes("<a "), html);
});

await t("a bare URL is left as text, never a link", () => {
  const html = P.renderBody("see https://example.com/x");
  assert.ok(!html.includes("<a "), `a URL became a link: ${html}`);
  assert.ok(html.includes("https://example.com/x"), html);
});

await t("a javascript: URL cannot become a link", () => {
  const html = P.renderBody("javascript:alert(1)");
  assert.ok(!html.includes("<a "), html);
  assert.ok(html.includes("javascript:alert(1)"), html);
});

await t("newlines become breaks in plain text", () => {
  assert.ok(P.renderBody("a\nb").includes("<br>"), P.renderBody("a\nb"));
});

console.log("long lines");

await t("a short line is untouched", () => {
  const r = P.clampText("hello", 10);
  assert.deepEqual(r, { text: "hello", clipped: false, full: "hello" });
});

await t("a long line is clamped but the whole text is kept", () => {
  const r = P.clampText("x".repeat(50), 10);
  assert.equal(r.clipped, true);
  assert.equal(r.text.length, 11);
  assert.equal(r.full.length, 50, "the full text was thrown away");
});

await t("a clamped line expands with no script", () => {
  const html = P.lineHtml({ who: "ada", text: "y".repeat(50), when: "12:00", limit: 10 });
  assert.ok(html.includes("<details"), `no expand affordance: ${html}`);
  assert.ok(html.includes('<div class="full">'), html);
});

await t("a short line has no expander", () => {
  const html = P.lineHtml({ who: "ada", text: "hi", when: "12:00" });
  assert.ok(!html.includes("<details"), html);
});

await t("a long code block is clamped too", () => {
  const html = P.lineHtml({ who: "ada", text: "```" + "z".repeat(50) + "```", when: "12:00", limit: 10 });
  assert.ok(html.includes("<details"), html);
});

console.log("time");

const T0 = Date.UTC(2026, 9, 3, 12, 0, 0);

await t("relative time for the recent past", () => {
  assert.equal(P.relTime(T0 - 10_000, T0), "just now");
  assert.equal(P.relTime(T0 - 5 * 60000, T0), "5m");
  assert.equal(P.relTime(T0 - 3 * 3600000, T0), "3h");
  assert.equal(P.relTime(T0 - 2 * 86400000, T0), "2d");
});

await t("relative time gives up on the distant past", () => {
  assert.equal(P.relTime(T0 - 40 * 86400000, T0), null,
    "a 40-day-old line still produced a relative label");
});

await t("a sender's clock ahead of ours is called out, not shown as negative", () => {
  assert.equal(P.relTime(T0 + 10 * 60000, T0), "ahead");
});

await t("no time at all is not a time", () => {
  assert.equal(P.relTime(null, T0), null);
  assert.equal(P.relTime(undefined, T0), null);
  assert.equal(P.relTime(NaN, T0), null);
});

await t("day labels are relative for today and yesterday", () => {
  assert.equal(P.dayLabel(new Date(T0).toISOString().slice(0, 10), T0), "Today");
  assert.equal(P.dayLabel(new Date(T0 - 86400000).toISOString().slice(0, 10), T0), "Yesterday");
});

await t("an older day gets a date, in UTC", () => {
  const d = new Date(T0 - 9 * 86400000).toISOString().slice(0, 10);
  const label = P.dayLabel(d, T0);
  assert.ok(!/Today|Yesterday/.test(label), label);
  assert.ok(/[A-Z][a-z]{2}/.test(label), label);
});

await t("the untitled bucket is labelled, never dated", () => {
  // Built by the real producer rather than by hand. The fixture used to be
  // `{ day: "UNTITLED", messages: [], untitled: true }`, which matched neither
  // the day value `byDay` uses (UNTITLED is the string "untitled") nor the
  // flag it sets on that bucket (`untimed`) — so the test passed while the page
  // rendered exactly this section as "Invalid Date". A hand-written fixture for
  // another module's output is only evidence about the fixture.
  const secs = P.daySections(
    N.byDay([{ at: null, sender: "alice", text: "no clock here" }]),
    T0,
  );
  assert.equal(secs.length, 1, "one bucket for one untimed line");
  assert.equal(secs[0].day, N.UNTITLED, "the bucket is the one byDay names");
  assert.equal(secs[0].label, "No time");
  assert.ok(!/Invalid|NaN/.test(secs[0].label), secs[0].label);
});

await t("a real day keeps its bucket and gains a label", () => {
  const day = new Date(T0).toISOString().slice(0, 10);
  const secs = P.daySections([{ day, messages: [] }], T0);
  assert.equal(secs[0].day, day);
  assert.equal(secs[0].label, "Today");
});

await t("the exact instant is always available for a hover", () => {
  assert.equal(P.isoAt(T0), new Date(T0).toISOString());
  assert.equal(P.isoAt(null), "no time given");
});

await t("the zone label names the reader's offset", () => {
  assert.match(P.tzLabel("UTC"), /^UTC\+00:00/);
  assert.match(P.tzLabel("Asia/Tokyo"), /^UTC\+09:00/);
});

await t("day buckets use UTC so two peers agree", () => {
  // 23:30 UTC on the 3rd is the 4th in Tokyo. `byDay` buckets in UTC, and the
  // label must bucket the same way or a peer in Tokyo and one in UTC would
  // file the same line under different days.
  const late = Date.UTC(2026, 9, 3, 23, 30, 0);
  assert.equal(P.daySections([{ day: new Date(late).toISOString().slice(0, 10) }], late)[0].label,
    "Today");
});

console.log("grouping");

await t("a grouped line drops the author block", () => {
  const full = P.lineHtml({ who: "ada", text: "hi", when: "12:00", avatar: "<img>" });
  const grouped = P.lineHtml({ who: "ada", text: "hi", when: "12:00", avatar: "<img>", grouped: true });
  assert.ok(full.includes('class="name"'), full);
  assert.ok(!grouped.includes('class="name"'), grouped);
  assert.ok(grouped.includes('class="indent"'), grouped);
  assert.ok(grouped.includes("12:00"), "a grouped line still needs its time");
});

await t("a line's title carries the exact instant", () => {
  const html = P.lineHtml({ who: "ada", text: "hi", when: "12:00", title: P.isoAt(T0) });
  assert.ok(html.includes(`title="${new Date(T0).toISOString()}"`), html);
});

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);