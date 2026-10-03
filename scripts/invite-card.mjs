#!/usr/bin/env node
// invite-card.mjs — turn an invite (a bare code, or a whole link, or a whole
// message with one in it) into a scannable card: the code, an icon drawn in
// the middle of it, a line of text under it, and the link printed underneath.
//
//   node scripts/invite-card.mjs '<code or link or message>' [options]
//
//   --out FILE        where to write the SVG          (default: invite-card.svg)
//   --caption TEXT    the words under the code        (default: from kant.config)
//   --icon PATH|URL   the picture in the middle       (default: from kant.config)
//   --alt TEXT        the picture's description       (default: from kant.config)
//   --origin URL      the site the link points at     (default: from kant.config)
//   --config FILE     which configuration to read     (default: web/kant.config)
//   --scale N         pixels per module               (default: 8)
//   --dark/--light C  the two colours                 (default: #000 / #fff)
//   --print           write the SVG to stdout instead of a file
//
// The behaviour is `Kant.InviteCard`: `inviteUrl_origin_prefix` (the payload is
// the whole link, so any camera app offers to open it), `inviteCardSvg_*` (the
// icon, the caption and the link really appear on the card),
// `inviteCard_icon_area_bound` (the icon stays inside the error-correction
// budget) and `inviteCardSvg_roundTrip` (the exported picture reads back as the
// same invitation).

import { readFile, writeFile } from "node:fs/promises";
import * as N from "../web/kant-net.mjs";
import * as S from "../web/kant-site.mjs";
import * as F from "../web/kant-flow.mjs";

const argv = process.argv.slice(2);
const flags = new Map();
const positional = [];
for (let i = 0; i < argv.length; i += 1) {
  if (argv[i].startsWith("--")) {
    const key = argv[i].slice(2);
    if (key === "print") flags.set("print", "1");
    else { flags.set(key, argv[i + 1]); i += 1; }
  } else positional.push(argv[i]);
}

const text = positional.join(" ");
if (!text) {
  console.error("usage: node scripts/invite-card.mjs '<code or link>' [--out FILE]");
  process.exit(2);
}

const root = new URL("../", import.meta.url);
const configPath = flags.get("config")
  ? new URL(flags.get("config"), `file://${process.cwd()}/`)
  : new URL("web/kant.config", root);

let cfg = { ...S.DEFAULT_CONFIG };
try {
  const parsed = S.parseConfig(await readFile(configPath, "utf8"));
  if (parsed && S.configWf(parsed)) cfg = parsed;
} catch {
  // no configuration file: the built-in one is a perfectly good default
}
if (flags.get("origin")) cfg = { ...cfg, origin: flags.get("origin") };

// `Kant.Join.findInvite`: the invitation is found however it arrives.
const inv = F.findInvite(text);
if (!inv) {
  console.error("no invitation in that text — expected a kzinvite code or a link containing one");
  process.exit(1);
}

const dress = {
  caption: flags.get("caption") ?? cfg.caption,
  icon: flags.get("icon") ?? cfg.picture,
  alt: flags.get("alt") ?? cfg.alt,
};

const link = F.inviteUrl(cfg, inv);
const svg = F.inviteCardSvg(cfg, dress, inv, {
  scale: Number(flags.get("scale") ?? 8),
  border: Number(flags.get("border") ?? 4),
  dark: flags.get("dark") ?? "#000",
  light: flags.get("light") ?? "#fff",
});

// The card must read back as the invitation it was made from, or it is no good.
const back = S.readCard(svg);
if (!back || N.parseInviteUrl(back.url) === null) {
  console.error("the card did not read back — refusing to write it");
  process.exit(1);
}

if (flags.get("print")) {
  process.stdout.write(svg);
} else {
  const out = flags.get("out") ?? "invite-card.svg";
  await writeFile(out, svg);
  console.error(`wrote ${out}`);
}

console.error(`room    ${N.inviteRoom(inv)}`);
console.error(`link    ${link}`);
console.error(`caption ${dress.caption}`);
console.error(`icon    ${dress.icon}`);
