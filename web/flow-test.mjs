// Checks for web/kant-flow.mjs against the statements proved in
// RequestProject/Kant/{Join,Onboarding,InviteCard,PlainText}.lean.
//
//   node web/flow-test.mjs

import * as F from "./kant-flow.mjs";
import * as N from "./kant-net.mjs";
import * as S from "./kant-site.mjs";
import * as K from "./kantzk.mjs";

let checks = 0;
const fail = [];
function ok(name, cond) {
  checks += 1;
  if (!cond) fail.push(name);
}
const eq = (name, got, want) =>
  ok(`${name} (got ${JSON.stringify(got)}, want ${JSON.stringify(want)})`, got === want);

const CONFIG = {
  origin: "https://kant.cicada71.net/",
  caption: "kant-zk-pastebin",
  picture: "./kant-logo.svg",
  alt: "the Kant pastebin logo",
};

const SECRET = Array.from({ length: 32 }, (_, i) => (i * 7 + 3) & 0xff);
const INV = N.invite("https://relay.example/", SECRET, "peer-38a3k", []);
const LINK = F.inviteUrl(CONFIG, INV);
const ROOM = N.inviteRoom(INV);

// ------------------------------------------------ Kant.InviteCard: the link

ok("the code carries the whole link", LINK.startsWith(CONFIG.origin + "#"));
ok("the code is no longer the bare payload", LINK !== N.copyInvite(INV));
eq("the link is the origin, a hash and the invitation",
  LINK.length, CONFIG.origin.length + N.copyInvite(INV).length + 1);
ok("the link is ASCII", K.isAscii(LINK));
ok("scanning the code recovers the invitation",
  JSON.stringify(N.parseInviteUrl(LINK)) === JSON.stringify(INV));
ok("a dressed invite link still fits in one code",
  LINK.length <= K.CHANNEL_CAPACITY.qr);

// ------------------------------------------- Kant.InviteCard: icon and text

const DRESS = F.dressOfConfig(CONFIG, "join my kant room");
const CARD = F.inviteCard(CONFIG, DRESS, INV);
eq("the card's link is the invite link", CARD.url, LINK);
eq("the card's picture is the custom icon", CARD.picture, DRESS.icon);
eq("the card's text is the custom caption", CARD.caption, DRESS.caption);

const SVG = F.inviteCardSvg(CONFIG, DRESS, INV);
ok("the custom icon really is drawn on the code", SVG.includes(K.escapeHtml(DRESS.icon)));
ok("the custom text really is printed under the code",
  SVG.includes(K.escapeHtml(DRESS.caption)));
ok("the whole link is printed on the card", SVG.includes(K.escapeHtml(LINK)));
ok("the code itself is a link to the room", SVG.includes(`<a href="${K.escapeHtml(LINK)}">`));

const NASTY = F.inviteCard(CONFIG, { caption: 'a"><script>x</script>', icon: '"><b>', alt: "<>" },
  INV);
const NASTY_SVG = S.renderCard(NASTY);
ok("no caption can break out of its element", !NASTY_SVG.includes("<script>"));
ok("no icon reference can break out of its element",
  !NASTY_SVG.includes('href=""><b>"'));

const BACK = F.readInviteCard(SVG);
ok("the exported picture still carries the card", BACK !== null && BACK.url === LINK);
ok("end to end: read the card back, scan the URL, get the invitation",
  BACK !== null && JSON.stringify(N.parseInviteUrl(BACK.url)) === JSON.stringify(INV));

const CHAT = F.inviteChatText(CONFIG, DRESS, INV);
ok("an invite card pasted into a chat window comes back whole",
  JSON.stringify(S.readChatText(CHAT)) === JSON.stringify(CARD));
ok("the chat text shows the whole link to a human", CHAT.includes(LINK));

// ------------------------------------------------------------- Kant.Join

const arrivals = [
  ["the bare code", N.copyInvite(INV)],
  ["a clean link", LINK],
  ["a link with a trailing newline", LINK + "\n"],
  ["a link with spaces round it", "  " + LINK + "  "],
  ["a link with a full stop after it", LINK + "."],
  ["a link in angle brackets", "<" + LINK + ">"],
  ["a link in a sentence", "hey, join me here: " + LINK + " — see you there"],
  ["a link on its own line in a message", "come in\n" + LINK + "\nbring snacks"],
  ["a code with a newline", N.copyInvite(INV) + "\n"],
  ["a link in parentheses", "(" + LINK + ")"],
  ["a link after a tab", "\t" + LINK],
  ["a link quoted", '"' + LINK + '"'],
];
for (const [what, text] of arrivals) {
  const i = F.findInvite(text);
  ok(`join accepts ${what}`, i !== null && N.inviteRoom(i) === ROOM);
}
ok("junk is not an invitation", F.findInvite("hello there, nothing here") === null);
ok("empty text is not an invitation", F.findInvite("") === null);
eq("both sides land in the same room", F.findRoom(LINK), ROOM);

// ------------------------------------------------------- Kant.Onboarding

const S0 = F.start();
eq("a first visit starts on the welcome screen", S0.screen, F.Screen.welcome);
eq("the camera starts off", S0.camera, false);

for (const t of F.SCREENS) {
  eq(`every screen is one tap away: ${t}`, F.step(S0, { type: "goto", screen: t }).screen, t);
}

const CAM = F.step(S0, { type: "startCamera" });
eq("the camera can be switched on", CAM.camera, true);
eq("switching the camera on shows the scan screen", CAM.screen, F.Screen.scan);
eq("the off button always works", F.step(CAM, { type: "stopCamera" }).camera, false);
eq("going back switches the camera off", F.step(CAM, { type: "back" }).camera, false);
eq("back always goes home", F.step(CAM, { type: "back" }).screen, F.Screen.welcome);
eq("leaving the room switches the camera off", F.step(CAM, { type: "leave" }).camera, false);
for (const t of F.SCREENS.filter((x) => x !== F.Screen.scan)) {
  eq(`tapping through to ${t} switches the camera off`,
    F.step(CAM, { type: "goto", screen: t }).camera, false);
}
eq("a code that was read switches the camera off",
  F.step(CAM, { type: "joinText", text: LINK }).camera, false);

// The camera never runs behind another screen, over every one-event
// extension of every state reachable in three events.
const EVENTS = [
  { type: "back" }, { type: "createRoom" }, { type: "copyLink" },
  { type: "startCamera" }, { type: "stopCamera" }, { type: "say" },
  { type: "leave" }, { type: "hush" }, { type: "unhush" },
  { type: "joinText", text: LINK }, { type: "joinText", text: "junk" },
  ...F.SCREENS.map((s) => ({ type: "goto", screen: s })),
];
let frontier = [S0];
let cameraOk = true;
for (let depth = 0; depth < 3; depth += 1) {
  const next = [];
  for (const s of frontier) {
    for (const e of EVENTS) {
      const t = F.step(s, e);
      if (t.camera && t.screen !== F.Screen.scan) cameraOk = false;
      next.push(t);
    }
  }
  frontier = next;
}
ok("the camera never runs behind another screen (exhaustive, depth 3)", cameraOk);

eq("the code carries exactly the link that is offered",
  F.qrText(CONFIG, DRESS, INV), F.shareText(CONFIG, INV));

const JOINED = F.step(S0, { type: "joinText", text: F.shareText(CONFIG, INV) });
eq("following the link puts you in the room", JOINED.inRoom, true);
eq("following the link lands you on the chat screen", JOINED.screen, F.Screen.chat);

eq("the guide asks first for a room", F.nextTask(S0.progress), F.Task.getIn);
const RUN1 = F.run(S0, [{ type: "createRoom" }, { type: "copyLink" }, { type: "say" }]);
eq("the scripted first run finishes", F.nextTask(RUN1.progress), null);
eq("...and leaves you in a room", RUN1.inRoom, true);
eq("...with the camera off", RUN1.camera, false);
const RUN2 = F.run(S0, [
  { type: "joinText", text: F.shareText(CONFIG, INV) },
  { type: "copyLink" },
  { type: "say" },
]);
eq("the other scripted first run finishes too", F.nextTask(RUN2.progress), null);
eq("...and leaves you in a room", RUN2.inRoom, true);

ok("a task once done stays done", (() => {
  let s = F.run(S0, [{ type: "createRoom" }, { type: "copyLink" }, { type: "say" }]);
  for (const e of EVENTS) {
    const t = F.step(s, e);
    if (!t.progress.gotIn || !t.progress.sharedIt || !t.progress.saidHello) return false;
  }
  return true;
})());

ok("there is always something to say", F.SCREENS.length > 0 && F.promptFor(S0).length > 0);
for (const t of Object.values(F.Task)) ok(`the guide has a line for ${t}`, F.prompt(t).length > 0);
eq("the guide sends you to the screen where the task is done",
  F.screenFor(F.nextTask(S0.progress)), F.Screen.welcome);
eq("the voice can be turned off", F.speech(F.step(S0, { type: "hush" })), "");
eq("with the voice on, the guide speaks",
  F.speech(F.step(S0, { type: "unhush" })), F.promptFor(S0));

// --------------------------------------------------------- Kant.PlainText

const TEXT = "The Critique of Pure Paste.\nSecond line, with punctuation!";
const POST = K.makePaste({
  id: "paste_20260902_000000",
  title: "Kant ZK Pastebin",
  content: K.utf8(TEXT),
  timestamp: "20260902000000",
});

eq("what is copied is what was typed", F.copyPlain(POST), TEXT);
ok("...and it is not the machine-readable envelope", F.copyPlain(POST) !== K.copyText(POST));

const WITH_META = F.copyPlainWithMeta(CONFIG, POST);
eq("the text survives the footer", F.bodyOf(WITH_META), TEXT);
const META = F.metaOf(WITH_META);
ok("the details survive too", META !== null);
eq("the footer's title is the post's title", META.title, POST.title);
eq("the footer's link is the whole page URL", META.link, S.pasteUrl(CONFIG, POST));
eq("the footer's address is the post's address", META.address, POST.witness);
eq("the footer's time is the post's time", META.posted, POST.timestamp);
ok("the whole link is printed in the footer", WITH_META.includes(S.pasteUrl(CONFIG, POST)));
eq("copying without the details gives only the text",
  F.copyPost(CONFIG, POST, false), TEXT);
eq("copying with the details gives the footer too",
  F.copyPost(CONFIG, POST, true), WITH_META);
ok("plain text with no footer has no details", F.metaOf(TEXT) === null);
eq("plain text with no footer is all body", F.bodyOf(TEXT), TEXT);

console.log(`${checks - fail.length}/${checks} checks passed`);
if (fail.length) {
  for (const f of fail) console.error(`FAIL: ${f}`);
  process.exit(1);
}
