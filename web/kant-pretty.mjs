// kant-pretty.mjs — how a room is shown, as pure functions.
//
// Everything here takes data and returns a string. No DOM, no network, no
// global state, so the whole of "how a transcript reads" is testable in Node
// without a browser — which matters, because the alternative is the failure
// this codebase keeps hitting: the rendering is the part with no tests.
//
// Two rules run through all of it:
//
//   1. Escape before you style. Every character that reaches innerHTML goes
//      through `esc` first, unless it came out of this file already. Body text
//      is attacker-controlled by definition — every peer in a room can post
//      anything — so a formatting feature that forgets this is a script
//      injection into everyone else's page.
//
//   2. Say what a time is. A room is read by people whose clocks disagree, and
//      `kzat` binds the SENDER's clock, not the reader's. Printing a bare
//      "14:03" is a claim about when that happened that is only true for one
//      person, so the label carries the zone and the exact instant is one
//      hover away.

// ------------------------------------------------------------- escaping

/** HTML-escape, including the quote forms, for text and attributes alike. */
export const esc = (s) => String(s ?? "")
  .replace(/&/g, "&amp;")
  .replace(/</g, "&lt;")
  .replace(/>/g, "&gt;")
  .replace(/"/g, "&quot;")
  .replace(/'/g, "&#39;");

/** Escape for a `data:` URI so it cannot break out of the attribute. */
export const escAttr = (s) => esc(s).replace(/`/g, "&#96;");

// -------------------------------------------------------------- time

const MIN = 60000, HOUR = 3600000, DAY = 86400000;

/** A short, honest "how long ago", or null once it stops being useful.
 *
 *  Null is a real return value and the caller must handle it: at some point
 *  "47 days ago" is worse than a date, and a transcript that shows both a
 *  relative form and a date for every line is unreadable. */
export function relTime(at, now = Date.now()) {
  if (at === null || at === undefined || !Number.isFinite(at)) return null;
  const d = now - at;
  // A clock that is ahead of ours is not "in the future by -3s": a sender's
  // clock can be wrong, and we cannot prove it is, so say so plainly.
  if (d < -MIN) return "ahead";
  if (d < 0) return "just now";
  if (d < 45_000) return "just now";
  if (d < HOUR) return `${Math.round(d / MIN)}m`;
  if (d < DAY) return `${Math.round(d / HOUR)}h`;
  if (d < 7 * DAY) return `${Math.round(d / DAY)}d`;
  return null;
}

const pad = (n) => String(n).padStart(2, "0");

/** The wall clock in the reader's zone: `14:03:22`. */
export const clockAt = (at, tz = undefined) => {
  const d = new Date(at);
  const parts = new Intl.DateTimeFormat("en-GB", {
    hour: "2-digit", minute: "2-digit", second: "2-digit",
    hour12: false, timeZone: tz,
  }).formatToParts(d);
  const g = (t) => parts.find((p) => p.type === t)?.value ?? "00";
  return `${g("hour")}:${g("minute")}:${g("second")}`;
};

/** The exact instant, for the `title` attribute. Always UTC, always exact:
 *  it is the one rendering of a sender's clock that nobody has to convert. */
export const isoAt = (at) => (Number.isFinite(at) ? new Date(at).toISOString() : "no time given");

/** The reader's zone, so two peers reading the same room can tell whose clock
 *  the wall-clock times are in.
 *
 *  Both the name and the offset are read for the *requested* zone. Reading the
 *  offset from the local zone while naming another one labels the reader's
 *  times with a zone they are not in, which is worse than printing nothing. */
export function tzLabel(tz = undefined) {
  const at = new Date();
  const part = (name) => new Intl.DateTimeFormat("en", { timeZone: tz, timeZoneName: name })
    .formatToParts(at).find((p) => p.type === "timeZoneName")?.value ?? "";
  const long = part("longOffset"), short = part("short");
  const m = long.match(/GMT([+-])(\d{2}):?(\d{2})?/);
  const off = m ? `${m[1] === "-" ? "-" : "+"}${m[2]}${m[3] ? `:${m[3]}` : ""}` : "+00:00";
  const suffix = short && short !== long ? ` ${short}` : "";
  return `UTC${off}${suffix}`;
}

/** A day bucket name: `Today`, `Yesterday`, else `Mon 12 Oct 2026`. */
export function dayLabel(day, now = Date.now()) {
  const key = (t) => new Date(t).toISOString().slice(0, 10);
  const today = key(now), yest = key(now - DAY);
  if (day === today) return "Today";
  if (day === yest) return "Yesterday";
  const d = new Date(`${day}T00:00:00Z`);
  const sameYear = d.getUTCFullYear() === new Date(now).getUTCFullYear();
  return d.toLocaleDateString("en-GB", {
    weekday: "short", day: "numeric", month: "short",
    year: sameYear ? undefined : "numeric", timeZone: "UTC",
  });
}

/** The transcript split into day sections, newest day last.
 *
 *  Built on `byDay`, which already owns the ordering rules — untimed lines go
 *  in their own bucket last rather than being invented a date. This only adds
 *  the labels, so the two cannot disagree about what belongs where. */
export function daySections(days, now = Date.now()) {
  return days.map((d) => ({ ...d, label: d.untitled ? "No time" : dayLabel(d.day, now) }));
}

// --------------------------------------------------------------- body

/** Split text into runs: code fences, inline code, and plain text.
 *
 *  Only fences and inline code. Bold, italics and links are deliberately NOT
 *  implemented — see `renderBody` — so this returns a flat list of typed
 *  spans and nothing has to be undone. */
export function spanBody(text) {
  const src = String(text ?? "");
  const out = [];
  let i = 0;
  const push = (kind, value) => { if (value) out.push({ kind, value }); };

  while (i < src.length) {
    // A fence runs to the next fence or to the end of the message. An
    // unterminated fence renders as code for the rest of the line rather than
    // leaking raw backticks into the page.
    const fence = src.indexOf("```", i);
    if (fence !== -1) {
      push("text", src.slice(i, fence));
      const close = src.indexOf("```", fence + 3);
      const body = close === -1 ? src.slice(fence + 3) : src.slice(fence + 3, close);
      push("code", body.replace(/^\n/, "").replace(/\n$/, ""));
      i = close === -1 ? src.length : close + 3;
      continue;
    }
    // Inline code: the next backtick, or to the end if there isn't one.
    const tick = src.indexOf("`", i);
    if (tick !== -1) {
      push("text", src.slice(i, tick));
      const close = src.indexOf("`", tick + 1);
      const body = close === -1 ? src.slice(tick + 1) : src.slice(tick + 1, close);
      push("code", body);
      i = close === -1 ? src.length : close + 1;
      continue;
    }
    push("text", src.slice(i));
    i = src.length;
  }
  return out;
}

/** Render a message body as safe HTML.
 *
 *  Code and nothing else. No links: a rendered link is a navigation to
 *  somewhere a peer chose, and the schemes that make `href` dangerous are
 *  exactly the ones that arrive in a chat room. Plain text is escaped, so a
 *  URL stays readable as a URL — a reader can still copy and check it, which
 *  is the behaviour you want when the sender is anonymous. */
export function renderBody(text) {
  const spans = spanBody(text);
  if (!spans.length) return "";
  return spans.map(({ kind, value }) =>
    kind === "code"
      ? `<code class="kcode">${esc(value)}</code>`
      : `<span class="ktext">${esc(value).replace(/\n/g, "<br>")}</span>`
  ).join("");
}

// --------------------------------------------------------- long lines

/** Clamp an over-long single line, reporting that it was clamped.
 *
 *  Measured on the source text, not on the rendered HTML — escaping can make
 *  the rendered string several times longer, so a limit expressed in
 *  characters is not a limit on what overflows the layout. It is the cheap,
 *  stable measure, and the CSS also wraps, so nothing is lost either way.
 *
 *  Nothing is hidden: `full` carries the whole thing and the caller puts it
 *  behind a `<details>`, so a reader who wants the tail gets it. */
export function clampText(text, limit = 400) {
  const s = String(text ?? "");
  if (s.length <= limit) return { text: s, clipped: false, full: s };
  return { text: `${s.slice(0, limit)}…`, clipped: true, full: s };
}

/** Clamp a whole body, so one long code fence behaves like a long line. */
export function renderBodyClamped(text, limit = 400) {
  const whole = clampText(text, limit);
  return { html: renderBody(whole.text), clipped: whole.clipped, full: whole.full };
}

// ------------------------------------------------------------ identity

/** The avatar chip for a peer: their picture, or their initial.
 *
 *  The fallback is an initial and not an identicon. That was offered and not
 *  chosen, so it is not here — but the fallback still cannot be blank, because
 *  most peers have never published a profile and a column of nothing is worse
 *  than a column of initials. */
export function avatarHtml({ dataUri = null, name = "", ref = "" }) {
  const initials = (String(name).trim()[0] ?? String(ref)[0] ?? "?").toUpperCase();
  if (dataUri) {
    // The mime comes from the peer's own manifest; only image/* is accepted
    // upstream, and an SVG data URI can script, so the type is re-checked here
    // rather than trusted because it was checked once.
    const safe = /^data:image\/(png|jpeg|gif|webp);base64,/.test(dataUri);
    if (safe) {
      return `<img class="avatar" src="${escAttr(dataUri)}" alt="" title="${escAttr(name || ref)}">`;
    }
  }
  return `<span class="avatar initial" title="${escAttr(name || ref)}" aria-hidden="true">${esc(initials)}</span>`;
}

/** One chat line as HTML.
 *
 *  `grouped` is true when the previous line came from the same peer within the
 *  same minute — the reader wants the author shown once at the top of a run,
 *  not repeated on every line of a paragraph.
 *
 *  A clamped body goes inside `<details>`, which gives click-to-expand with no
 *  script at all — the whole point of doing this in a string is that it also
 *  works where there is no DOM to attach a handler to. */
export function lineHtml({
  who, avatar = "", when = "", text, title = "", grouped = false, mine = false, limit = 400,
}) {
  const body = renderBodyClamped(text, limit);
  const inner = body.clipped
    ? `<details class="clip"><summary>${body.html}</summary>` +
      `<div class="full">${renderBody(body.full)}</div></details>`
    : body.html;
  return `<div class="line${grouped ? " grouped" : ""}${mine ? " mine" : ""}">` +
    (grouped
      ? `<span class="indent"></span>`
      : `<span class="who">${avatar}<span class="name">${esc(who)}</span></span>`) +
    `<span class="at" title="${escAttr(title)}">${esc(when)}</span>` +
    `<span class="body">${inner}</span></div>`;
}

/** A day separator. */
export const dayHtml = (label) =>
  `<div class="daysep"><span>${esc(label)}</span></div>`;