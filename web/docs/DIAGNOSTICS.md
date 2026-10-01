# Diagnostics: why two clients on one machine were not connecting

Two browsers open on the same laptop used to sit there, each showing a room,
neither hearing the other, and neither saying why.  This document is about
the three things that changed:

1. the client now finds a relay it can actually use, including the one that
   served the page;
2. every step of every transport is written into one log, and nothing is
   swallowed;
3. the whole run can be read, saved and shared from `web/diag.html`.

Before any of that, though, check *what you are holding*: a share card
(`kzcard:`) and a page link name a page and carry no room, and only an
invitation (`kzinvite:`) can join two clients. `diag.html` → **What is this
code?** and `node scripts/kant-debug.mjs` say which one a pasted block is.
See [`CARD-DEBUG.md`](CARD-DEBUG.md).

Everything here is specified in Lean first — `RequestProject/Kant/Connectivity.lean`
and `RequestProject/Kant/Diagnostics.lean` — and the browser client is a
transcription of those modules, pinned to golden vectors that Lean computes
(`RequestProject/Kant/Demo.lean`, checked by `web/diag-test.mjs`).

---

## 1. The bug

`web/kant.config` ships with `relay =` empty, and the client used to refuse
any relay that was not written there.  Two *tabs* of one browser find each
other with no server at all, over a `BroadcastChannel`; two *browsers* — or
a normal window and a private one, or two profiles — share nothing.  So on
one machine, with no relay configured, there was no transport between them
at all.  Worse: if the page had been served by `node server/relay.mjs
--static web`, the relay was right there on the origin, and the client
ignored it.

The rule is now `Kant.Connectivity.effectiveRelay`:

| configured relay | it answers | origin answers `/health` as a relay | relay used |
| --- | --- | --- | --- |
| set | yes | — | the configured one |
| set | no  | — | none — verdict `relay-down` |
| empty | — | yes | the page's own origin |
| empty | — | no  | none — verdict `only-this-browser` |

Proved in `Connectivity.lean`:

* `effectiveRelay_configured` — a configured relay that answers always wins;
* `effectiveRelay_selfHosted` — with nothing configured, a self-hosting
  origin is used;
* `effectiveRelay_needs_probe` — an origin that has not answered a probe is
  never used, so the client never pretends to have a transport it lacks;
* `two_browsers_one_machine_linked` — two browsers on one machine that share
  a relay and a room are linked;
* `two_browsers_one_machine_stuck` — and without one they are not, however
  many tabs are open.

The upshot for a user: serving the page with

```sh
node server/relay.mjs --static web
```

is now enough for two browsers on one machine to talk, with no
configuration at all.

## 2. The log

`Kant.Diagnostics` gives the run a shape rather than a pile of strings.

An **event** is a moment (`ms` since the page opened), a **level**
(`info`, `warn`, `error`), an **area**, a short text and a detail.  The
areas are the places a connection can fail: `config`, `probe`, `relay`,
`socket`, `bus`, `mesh`, `signal`, `ingest`, `app`.

The **log** is a bounded ring: at most `cap` events, oldest dropped first,
with a count of how many were dropped, so a long run cannot exhaust memory
and cannot silently mislead either.  Proved: `Log.add_length_le` (the cap
holds), `Log.add_getLast` (the newest event is never the one dropped),
`Log.add_total` (the total is honest about the drops), `Log.Wf.record`.

Each event prints as one hex line and reads straight back:
`parseEvent_printEvent`, and for a whole log `parseLog_renderLog`.  That is
what makes a run shareable as text without any escaping question.

Nothing is swallowed any more.  `web/kant-net.mjs` had bare `catch {}`
around the relay post, the signalling post and the poll loop; every one of
them now records what failed and why — the URL, the status, the exception —
in the `relay`, `signal` and `socket` areas.  `RelaySocket` logs open,
close and error; `LocalBus` logs whether `BroadcastChannel` exists at all
and what crosses it; `PeerMesh` logs every ICE and data-channel state
change.  The page itself captures `window.onerror` and
`unhandledrejection` into the same log.

A related fix lives in the poll loop: with no relay in use it used to
return immediately and go straight round again, which starves every timer
in the page and floods the log with one line thousands of times a second.
It now idles, and says "nothing to poll" once
(`web/diag-test.mjs` checks both).

### Secrets

A log that cannot be shared is not much use, and a log that leaks the room
secret must not be shared.  `Log.share` keeps exactly the events that quote
none of the given secrets: `share_clean` and `share_no_secret` say nothing
secret survives, `share_keeps` says nothing else is thrown away, and
`report_events_clean` carries that through to the shared report.  Rooms are
printed as an eight-character handle, `ref` (`ref_length`, `ref_ne`).

## 3. The diagnostics page

**In the app** (`web/index.html`, the "more" screen) there is a Diagnostics
card: the current verdict in words, a live tail of the last forty events,
and three buttons — copy the whole run, save it as a file, or open the
diagnostics page with this run handed to it.

**`web/diag.html`** is a standalone page that needs nothing but itself:

* the verdict and what to do about it;
* the whole run as a table (time, level, area, text, detail);
* *Run the checks on this machine* — probes the origin and the configured
  relay, tries a `BroadcastChannel`, tries a `RTCPeerConnection`, and
  records each result as an event;
* *Copy the whole run* / *Save it as a file* / *Copy a link to it* (the run
  travels in the URL fragment, truncated from the oldest end at about 8000
  characters so the link stays usable);
* *Read somebody else's run* — paste it or open a file; `findReport` picks
  the report out of surrounding chat or an email;
* *Load the run from before the last reload* — the run is written into
  `localStorage` as it happens and rotated on reload, which is exactly what
  you want after a crash.

### The verdicts

| verdict | what it means |
| --- | --- |
| `ok` | you and the other client share a room and a transport |
| `no-room` | open a room, or paste an invite link |
| `room-mismatch` | the link pasted is not the link that was shown |
| `relay-down` | the configured relay did not answer; check `relay =` in `kant.config` |
| `only-this-browser` | two separate browsers with no relay between them; serve the page with `node server/relay.mjs --static web`, or set `relay =` |
| `no-transport` | no relay, and no same-browser channel |

`diagnose_eq_ok_iff` proves the verdict is `ok` exactly when the two clients
are linked — the page cannot say "fine" about a pair that cannot talk — and
`explain_injective` proves the six explanations are six different sentences.

## 4. The relay's own log

```sh
node server/relay.mjs --port 8787 --static web --log relay.log
```

Every request is written down: the time, the method, the path with the room
reduced to an eight-character handle, the status, the number of lines and
how long it took; plus socket open/close/error and every refusal (a body or
line over the limit).  Rooms are never printed in full, so a relay log can
be shared the way a client run can.  `--quiet` keeps stdout clean, and the
module keeps quiet by default when it is imported as a library rather than
run.

## 5. Reproducing a two-browser session on one machine

```sh
node server/relay.mjs --port 8787 --static web --log relay.log
# then open http://localhost:8787/ in two different browsers
```

Start a room in the first, copy the link, paste it into the second.  Both
Diagnostics cards should read `ok`.  If they do not, open `diag.html` in
each, press *Run the checks on this machine*, and share both runs: between
the verdict, the probe results and the relay's own log, the failing step is
in there.

The same session is exercised without a browser by `node web/diag-test.mjs`,
which starts a real relay subprocess and drives two clients with the
same-browser channel switched off.
