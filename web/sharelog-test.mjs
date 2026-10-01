// Conformance checks for web/kant-sharelog.mjs against the golden vectors
// Lean checks in RequestProject/Kant/ShareLog.lean and
// RequestProject/Kant/Handoff.lean (the `#guard` blocks), plus end-to-end
// exercises of the two things the buttons do: share the run (and post it
// to the store), and run a whole conversation by hand in a chat with no
// server anywhere.
//
//   node web/sharelog-test.mjs

import * as SL from "./kant-sharelog.mjs";
import * as K from "./kantzk.mjs";
import * as D from "./kant-diag.mjs";
import * as U from "./kant-uucp.mjs";

let checks = 0;
const fail = [];
function ok(name, cond) {
  checks += 1;
  if (!cond) fail.push(name);
}
function eq(name, got, want) {
  ok(`${name} (got ${JSON.stringify(got)}, want ${JSON.stringify(want)})`, got === want);
}

// ------------------------------------------------------ the sample run

const EV1 = D.event(0, 12, "info", "app", "page opened", "https://example.org/");
const EV2 = D.event(1, 40, "warn", "probe", "the relay did not answer", "timeout");

const fakeLog = (events) => ({
  events,
  dropped: 0,
  share: (secrets) => events.filter((e) => D.clean(secrets, e)),
});

const report = SL.shareReport({
  log: fakeLog([EV1, EV2]),
  verdict: "noRoom",
  room: "swordfish",
  relay: "https://relay.example.org",
});

// --- the golden vectors, byte for byte what Lean computes ----------------

eq("the room travels only as its handle", report.room, "5799c0f1");
ok("the room itself is not in the shared run", report.room !== "swordfish");
eq("the shared run has the length Lean says", SL.logText(report).length, 255);
eq("the shared run is what Lean renders", SL.logText(report),
  "6b7a64696167:02:3537393963306631:68747470733a2f2f72656c61792e6578616d706c652e6f7267\n" +
  "6b7a6c6f67::0c:01:09:70616765206f70656e6564:68747470733a2f2f6578616d706c652e6f72672f\n" +
  "6b7a6c6f67:01:28:02:02:7468652072656c617920646964206e6f7420616e73776572:74696d656f7574");
eq("the posted run has the address Lean computes",
  SL.logPaste(report, { id: "run_1", timestamp: "1700000000" }).witness,
  "8b0d60a6d87089066612b9b45273c16b078fb92940fd3c78dbdee66be14716e5");
eq("three chat messages carry the whole run", SL.chatParts(100, report).length, 3);
eq("the title of a posted run", SL.LOG_TITLE, "the run so far");
eq("the copy instruction", SL.SAY_COPY, "copy this and send it in the chat");
eq("the paste instruction", SL.SAY_PASTE, "paste what they sent you into the box");
eq("the thread instruction", SL.SAY_PART, "send this message, then the next one");

// --- as text -------------------------------------------------------------

const readBack = SL.readShared(SL.logText(report));
eq("a shared run reads back: verdict", readBack.verdict, report.verdict);
eq("a shared run reads back: room", readBack.room, report.room);
eq("a shared run reads back: relay", readBack.relay, report.relay);
eq("a shared run reads back: events", readBack.events.length, 2);
eq("…and their text", readBack.events[1].text, "the relay did not answer");

const wrapped = `hey, here is the log\n\n${SL.logText(report)}\n\nthanks!`;
eq("a run pasted into a chat window is still found",
  SL.readShared(wrapped).events.length, 2);
ok("the readable form carries the machine-readable block",
  SL.readShared(SL.shareText(report)).events.length === 2);

// --- secrets never travel ------------------------------------------------

const SECRET = "hunter2-the-room-secret";
const leaky = D.event(2, 55, "info", "signal", "joined the room", `secret ${SECRET}`);
const filtered = SL.shareReport({
  log: fakeLog([EV1, leaky]),
  verdict: "ok",
  room: SECRET,
  relay: "",
});
eq("an event quoting the secret is withheld", filtered.events.length, 1);
ok("the secret is nowhere in the shared text", !SL.logText(filtered).includes(K.hexEncode(K.asciiBytes(SECRET))));
ok("nor is the room", filtered.room !== SECRET);
ok("the event that quotes nothing is kept", filtered.events[0].text === "page opened");

// --- as a post in the store ---------------------------------------------

const store = new K.Store();
const posted = SL.postLog(store, report, { id: "run_1", timestamp: "1700000000" });
ok("posting the run gives it an address", store.has(posted.witness));
eq("the store holds one block", store.entries.length, 1);
ok("the run is in the feed", K.feed(store).some((p) => p.witness === posted.witness));
eq("the posted title", store.get(posted.witness).title, "the run so far");

const again = SL.postLog(store, report, { id: "run_1", timestamp: "1700000000" });
ok("posting the same run twice is a no-op", again.already);
eq("…and adds no block", store.entries.length, 1);

const recovered = SL.readPostedLog(store.get(posted.witness));
eq("the posted run parses back", recovered.events.length, 2);
eq("…with the same handle", recovered.room, report.room);
eq("the link to a posted run",
  SL.logLink("https://example.org/index.html", posted.paste),
  `https://example.org/index.html#${posted.witness}`);

// --- as chat messages ----------------------------------------------------

const parts = SL.chatParts(100, report);
ok("every chat message fits in a tweet", parts.every((p) => p.length <= U.CARRIER_CAPACITY.tweet));
ok("every chat message is plain ASCII", parts.every((p) => K.isAscii(p)));
eq("the messages reassemble into the run", SL.readChatParts(parts).events.length, 2);
const shuffled = [parts[2], parts[0], parts[1]];
eq("…in any order", SL.readChatParts(shuffled).events[1].text, "the relay did not answer");
eq("a missing message is refused", SL.readChatParts(parts.slice(1))?.events?.length ?? null, null);
eq("the count matches", SL.chatPartCount(100, report), parts.length);
ok("a bigger carrier takes bigger parts", SL.partLimitFor("dm") > SL.partLimitFor("tweet"));

const steps = SL.logScript(100, "you", report);
eq("one step per message", steps.length, parts.length);
ok("no step needs a server", SL.serverless(steps));
eq("the steps carry exactly the messages", SL.codes(steps).join("|"), parts.join("|"));
eq("the run survives following the steps", SL.readChatParts(SL.codes(steps)).events.length, 2);
ok("a step reads as an instruction", SL.stepLine(steps[0]).startsWith("1. you: send this message"));

// --- carrying a post by hand --------------------------------------------

const note = K.makePaste({ id: "n1", title: "a note", content: "hello", timestamp: "t" });
const theirStore = new K.Store();
const carried = SL.carry(theirStore, SL.carryText(note));
ok("a post carried by hand arrives", carried.accepted && theirStore.has(note.witness));
eq("…at the very same address", carried.witness, note.witness);
SL.carry(theirStore, SL.carryText(note));
eq("carrying it twice changes nothing", theirStore.entries.length, 1);
ok("both sides agree by content", SL.agrees(note, theirStore.get(note.witness)));
ok("garbage is refused", !SL.carry(theirStore, "not a post at all").accepted);
eq("…and nothing is added", theirStore.entries.length, 1);

const carriedRun = SL.carry(new K.Store(), SL.carryText(posted.paste));
ok("the posted run travels by hand too", carriedRun.accepted);
eq("…keeping its address", carriedRun.witness, posted.witness);

// --- a whole conversation, by hand, with no server ------------------------

const room = K.witness(Array.from("a shared passphrase"));
const alice = U.SneakerNode.blank("alice");
const bob = U.SneakerNode.blank("bob");
alice.write(room, "is anyone there?");

// step 1: alice copies her bag; step 2: bob pastes it
const step1 = alice.bag();
bob.paste(step1);
// step 3: bob writes a reply and copies his bag; step 4: alice pastes it
bob.write(room, "yes, right here");
const step3 = bob.bag();
alice.paste(step3);

eq("bob heard alice", bob.view().length, 2);
eq("alice heard bob", alice.view().length, 2);
eq("both sides show the same conversation",
  JSON.stringify(alice.view()), JSON.stringify(bob.view()));
ok("no server was involved", true);

const plan = SL.script({ me: "alice", them: "bob", mine: step1, theirsAfter: step3 });
eq("the script has four steps", plan.length, 4);
eq("two codes go into the chat", SL.codes(plan).length, 2);
ok("no step of the script needs a server", SL.serverless(plan));
eq("step one is yours", plan[0].actor, "alice");
eq("step two is theirs", plan[1].move.kind, "pasteIn");
ok("the codes are the two bags", SL.codes(plan)[0] === step1 && SL.codes(plan)[1] === step3);
ok("every code is plain text", SL.codes(plan).every((c) => K.isAscii(c)));

// a bag too big for one message goes as a thread, and still arrives
for (let i = 0; i < 40; i += 1) alice.write(room, `line number ${i} of a long conversation`);
const big = alice.bag();
const carol = U.SneakerNode.blank("carol");
const threadParts = U.bagForCarrier(big, "tweet");
ok("a long conversation needs several messages", threadParts.length > 1);
ok("each of them fits in a tweet",
  threadParts.every((p) => p.length <= U.CARRIER_CAPACITY.tweet));
carol.paste(threadParts.join("\n"));
eq("and the whole conversation arrives", carol.view().length, alice.view().length);

console.log(`${checks - fail.length}/${checks} checks passed`);
if (fail.length) {
  for (const f of fail) console.error(`FAIL: ${f}`);
  process.exit(1);
}
