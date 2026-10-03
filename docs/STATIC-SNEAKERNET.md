# The static sneakernet: DMs, tweets and bang paths, with no relay

The relay of `docs/DISCOVERY-AND-CHAT.md` is now optional. This document
describes the mode that removes it: a **static** system in which the only
thing that ever moves state is a human moving a code — a direct message,
a tweet thread, a QR code on a screen, a link in an address bar, a file
on a USB stick.

The rule, stated once and then proved:

> **You are exactly as up to date as the last URL or QR code you pasted**
> — unless you are connected to a relay, in which case the relay keeps
> you current.

## The model

Specified and proved in `RequestProject/Kant/Uucp.lean`.

* **Spool.** A node (`Kant.Uucp.Node`) is a name, the self-certifying
  chat lines it holds (`Kant.Relay.Msg`), and a counter for its own
  lines. It has no connection to anything.
* **Mailbag.** `packBag` renders everything a node holds as one line of
  ASCII, tagged `kzbag`, whose fields are the printed chat lines.
  `openBag` reads it back: `openBag_packBag`.
* **Paste.** `Node.paste` merges a bag; `Node.sneakernet` merges a pile
  of them. Pastes are idempotent (`paste_idem`), order-free
  (`paste_perm`) and never lose anything (`paste_monotone`).
* **Freshness.** `Node.mem_sneakernet_iff` says a node holds exactly
  what it already held plus the contents of the bags it was given — and
  nothing else. `paste_bad` says an unreadable code changes nothing at
  all. Those two together are the rule quoted above.
* **Canonical codes.** `bag_canonical`: two nodes that know the same
  lines emit byte-identical bags, so a code can be pinned, cached and
  deduplicated by its own text.
* **The relay is redundant.** `sneakernet_matches_relay`: a node that
  starts empty and pastes a bag ends up displaying *exactly* the
  transcript a relay client displays after being handed the same
  messages as lines. Nothing is lost by removing the server.

## Carriers

`Kant.Uucp.Carrier` fixes the caps the codes have to live inside:

| carrier | characters |
|---|---|
| tweet | 280 |
| direct message | 10 000 |
| QR code (version 40, byte mode) | 2 953 |
| address bar | 2 000 |
| profile biography | 160 |
| picture alt text | 1 000 |

A bag that does not fit goes out as a numbered **thread**: `thread 100 s`
cuts it into parts tagged `kzleg`, each carrying its sequence number and
the total. `thread_fits_tweet` proves every part is inside the
280-character limit; `readThread_thread` and `readThread_perm` prove the
parts reassemble exactly, and that they may be posted, screenshotted and
collected **in any order** — which is what makes a tweet thread, a
carousel, or four QR codes photographed at random a usable transport.

## Store and forward: the bang path

Nobody has to be online at the same time as anybody else. `handoff`
proves one bag catches the receiver up with the sender; `uucp_path`
proves A → C → B delivers when C simply hands on its own bag later;
`uucp_route` iterates that along a whole path of couriers `a!c!d!b`.
`exchange_agree` proves that two bags, one each way, leave both sides
displaying the same transcript — with no relay, no server and no
network.

## The one exception

`relay_keeps_current` is the other half of the rule: a node that *is*
connected — to the relay of `Kant.Relay`, to a peer data channel, to
anything handing it lines — takes those lines exactly as it takes a
pasted bag, and holds everything the room carries with nothing pasted.
`stale_without_paste` is its mirror: paste nothing, poll nothing, and
your view does not change at all.

## Trust

A courier may drop mail, delay it or refuse to carry it. It cannot
forge it: every line carries a witness over its own fields, and
`bag_rejects_forgery` shows that a bag containing one doctored line does
not open **at all**, so a tampered DM changes nothing rather than
poisoning the spool. As with the relay, line contents are not
encrypted: anybody holding the code can read what it carries.

## The static server

`Kant.Uucp.Site` is the whole of the server side: a read-only map from
path to text. `serve_static` proves that serving a request leaves the
site unchanged — there is no session, no queue and no server-side state
to lose. `visitor_catches_up` proves a visitor who pastes the published
page is caught up with the publisher, and `snapshot_is_stale` proves the
converse and important half: a line written **after** publication is
provably invisible until a fresher code is pasted.

### The generator

```
node scripts/sneakernet.mjs init    site --name alice
node scripts/sneakernet.mjs write   site "something to say"
node scripts/sneakernet.mjs publish site --base https://alice.example/s/
```

`publish` writes a directory of plain files:

| file | what it is |
|---|---|
| `bag.txt` | the whole spool as one line — paste this into a DM |
| `thread.txt` | the same bag cut into tweet-sized numbered parts |
| `link.txt` | the same bag as a link, carried in the fragment |
| `qr/*.svg` | the same bag as one QR code, or one per part |
| `index.html` | a readable page that shows all of the above |

Copy that directory anywhere that serves files: a pages host, an object
store, a pinned IPFS directory, an `archive.org` item, a USB stick.
There is no API to deploy and nothing to keep running.

Receiving is the mirror image:

```
node scripts/sneakernet.mjs paste  site bag.txt        # a DM you were sent
node scripts/sneakernet.mjs paste  site thread.txt     # a whole tweet thread
node scripts/sneakernet.mjs paste  site "https://…/#…" # a link
node scripts/sneakernet.mjs status site
```

Anything that does not certify itself is refused with a non-zero exit
status, and the spool is left untouched.

`node scripts/sneakernet.mjs serve site --port 8080` is a convenience for
looking at the directory locally. It answers `GET` with files and
nothing else; it is not part of the protocol.

## In the browser

Section 8 of `web/index.html` — “Sneakernet: keep going with no relay at
all” — is the same thing with no tooling: write lines offline, copy the
bag, copy the link, show the QR code, cut the bag into tweets, paste
what somebody sent you, or scan their code with the camera. The spool
lives in `localStorage`, so the page is as fresh as the last code pasted
into it and no fresher. A link whose fragment carries a bag catches the
page up the moment it is opened.

The client code is `web/kant-uucp.mjs`, a transcription of the Lean
module; `node web/uucp-test.mjs` checks it against vectors computed by
Lean and runs the protocol end to end — bags in DMs, threads collected
out of order, a bang path, a published page and the staleness that
follows.

## What is proved, and what is not

Proved, in Lean, with no `sorry`: everything named above.

Not proved: the JavaScript and the CLI. They are transcriptions, pinned
to Lean-computed vectors by the test scripts, not verified artefacts.
Encryption of line contents is still out of scope — the sneakernet
changes who carries your words, not who can read them.
