# How clients find each other, and the server you run

Short answer:

1. **Out of band, once**: one client shows a **chat code** (a QR code, or the
   same text as a link).  The other scans or pastes it.  That code carries a
   secret; the *room* both clients then use is the **digest** of that secret.
2. **In band, after that**: both clients talk to a **relay** — an append-only
   mailbox, one log per room.  They post their own peer announcements and read
   everybody else's, which is how they discover each other.  You can run that
   relay on Cloudflare or on your own Linux box; both are in `server/`.
3. **Directly, when the browsers can**: the relay also carries the WebRTC
   offer/answer/ICE lines, so after the introduction the two browsers open a
   **direct data channel** and the relay is no longer in the path.
4. **With no server at all**: other tabs of the same browser find each other
   over a `BroadcastChannel`, and a code can always be carried by hand — a
   screenshot, a photo of a screen, a pasted line.

Nothing in that list is trusted.  Every line a client accepts — from a relay,
a peer, a scan or a paste — is re-checked against its own witness first.

---

## The pieces, and where they are proved

| Concept | Lean | Browser | Server |
|---|---|---|---|
| Peer announcement (`kzpeer`) | `Kant.Rendezvous.Announce`, `printAnnounce` | `printAnnounce` in `web/kant-net.mjs` | carried, never parsed |
| Roster and gossip | `Roster.merge`, `Roster.best` | `rosterMerge`, `rosterBest` | — |
| Chat invitation (`kzinvite`, the QR code) | `Invite`, `copyInvite`, `roomOf` | `copyInvite`, `roomOf`, `web/kant-qr.mjs` | — |
| Chat line (`kzchat`) | `Kant.Relay.Msg`, `printMsg`, `parseMsg` | `printMsg`, `parseMsg` | carried, never parsed |
| Signalling line (`kzsig`) | — (transport plumbing) | `printSignal`, `parseSignal` | carried, never parsed |
| Room mailbox | `Kant.Relay.Server` (`post`, `lines`, `fetch`) | `Server` (local mirror) | `server/relay.mjs`, `server/worker.js` |
| Transcript | `transcript`, `clients_agree` | `transcript` | — |

The theorems that matter for "can these two actually find each other, and can
they trust what they see":

* `Kant.Rendezvous.pasteInvite_copyInvite` — the code reads back as the
  invitation that was shown;
* `Kant.Rendezvous.scan_same_room` — both sides compute the same room;
* `Kant.Rendezvous.invite_fits_qr` — the invitation fits in one QR code;
* `Kant.Rendezvous.Roster.mem_merge_iff`, `merge_perm` — gossip adds exactly
  what was heard, in any order;
* `Kant.Rendezvous.Roster.discovery_transitive` — A learns everybody C
  advertised, through B;
* `Kant.Rendezvous.best_congr` — clients that heard the same announcements dial
  the same address;
* `Kant.Relay.Server.fetch_since` — polling with the cursor you were given
  returns exactly what was posted since;
* `Kant.Relay.poll_lossless` — polling in stages sees the same lines;
* `Kant.Relay.parseMsg_eq_none_of_mismatch`, `relay_cannot_forge` — a doctored
  or invented line is dropped, not displayed;
* `Kant.Relay.clients_agree` — same lines, any order, any route ⇒ same chat;
* `Kant.Relay.discover_via_relay` — announcing into a room makes you findable.

`RequestProject/Kant/Demo.lean` runs the same objects as build-time `#guard`s,
and `web/net-test.mjs` checks the browser transcription against the strings
Lean computed, then runs two clients through the real relay.

---

## The chat code

A code is one line of ASCII: `kzinvite`, then the relay URL, the shared secret,
the inviting peer's name, and any direct addresses it already has, each hex
encoded and joined with `:`.  For example (secret `kant-zk demo secret`):

```
6b7a696e76697465:68747470733a2f2f72656c61792e6578616d706c652e6f7267:6b616e742d7a6b2064656d6f20736563726574:616c696365:032f646e73342f72656c61792e6578616d706c652e6f72672f7463702f3434332f777373:0269726f687469636b657431
```

* The **room** is `witness(secret)` —
  `bd71dd50a1ee00eaa91ea3fb701d151f8bc3059f81b1766c51ea8736f88acec1` for that
  secret.  The relay only ever sees the room, never the secret.
* The same line travels as the fragment of a link, so `https://your.site/#kzinvite:…`
  works for people who cannot scan.
* `web/kant-qr.mjs` renders it: a self-contained QR encoder (byte mode, level
  L, versions 1–40, automatic mask), no library and no CDN, so the code shows
  offline.  A typical invitation is version 9.

The room is a digest, so the relay cannot enumerate rooms it was not told
about, and two people with the same code — and only they — agree on where to
meet.

---

## The relay protocol

Four calls.  Both implementations answer identically, and a client cannot tell
them apart.

```
GET  /health                            -> { ok, name: "kant-zk-relay", version }
POST /room/{room}    body: one line per newline
                                        -> { ok, cursor, accepted }
GET  /room/{room}?cursor=N              -> { ok, cursor, lines, truncated }
GET  /room/{room}?cursor=N&wait=25      -> the same, held open until something arrives
WS   /ws/{room}?cursor=N                -> pushes { ok, cursor, lines }; send lines as text
```

`cursor` is the absolute length of the room's log — exactly the second
component of `Kant.Relay.Server.fetch`.  Poll with the cursor you were last
given and you get precisely the lines posted since (`fetch_since`); poll from
`0` and you get the whole room, which is how a late joiner catches up.

Deviations from the proved model, both about memory rather than meaning, and
both reported honestly to the client:

* a line longer than 256 KB is rejected with `413`;
* a room keeps its most recent 4096 lines; a poll from a cursor that has been
  trimmed away returns `truncated: true` together with everything still held.

### Running it on your Linux server

```sh
git clone <this repo> /opt/kant-zk-pastebin
cd /opt/kant-zk-pastebin
node server/relay.mjs --port 8787 --host 127.0.0.1 --static web
```

Zero dependencies: Node's own `http`, plus a small RFC 6455 implementation for
the WebSocket route.  `--static web` also serves the browser client, which
means the page and its relay share an origin and no CORS is involved.

For a permanent install:

```sh
sudo useradd --system --home /opt/kant-zk-pastebin kantzk
sudo cp server/kant-relay.service /etc/systemd/system/
sudo systemctl enable --now kant-relay
sudo cp server/nginx.conf.example /etc/nginx/sites-available/kant-zk   # TLS + WS upgrade
```

Then use `https://relay.example.org` as the relay in the client, or just open
the page from that host and leave the relay box at its default (same origin).

### Running it on Cloudflare

```sh
cd server
npx wrangler deploy
```

`server/worker.js` puts one Durable Object per room in front of the same
protocol, with the log persisted in the object's storage and WebSockets
handled natively.  `wrangler.toml` has an optional `[assets]` block if you want
Cloudflare to serve `web/` from the same origin too.

---

## What a client does, step by step

`KantNode` in `web/kant-net.mjs` is the whole thing:

```js
const alice = new KantNode({ peer: "alice", relay: "https://relay.example.org" });
const code  = alice.createRoom();       // fresh secret, room = digest(secret)
// …show `code` as a QR (qrEncode/qrSvg) or copy it…

const bob   = new KantNode({ peer: "bob" });
bob.joinInvite(code);                   // same room, and alice recorded as a peer
bob.connect();                          // BroadcastChannel + WebRTC mesh
await bob.announceSelf();               // posts a kzpeer line into the room
await bob.startPolling({ wait: 25 });   // long-polls the relay
await bob.say("hello");                 // posts a kzchat line
bob.view();                             // the transcript, in canonical order
```

* `publish` sends by every route it has: direct data channels first, then the
  same-browser bus, then the relay.
* `ingest` is the only way anything enters the client, and it drops whatever
  does not certify itself.  That is what makes the route irrelevant to the
  result (`clients_agree`).
* `dialKnownPeers` offers a WebRTC channel to everybody in the roster; the
  offer, answer and ICE candidates go through the room as `kzsig` lines, so no
  extra signalling server is needed.

## Privacy and trust, stated plainly

* The relay sees room names (digests), line lengths, and IP addresses.  It does
  not see the room secret, and it cannot forge, edit or reorder a line into
  something a client will believe.
* Nothing here is encrypted yet: a line's *content* is visible to the relay.
  The room secret is already shared between the participants and would be the
  natural key for that; it is not wired up, and this document does not pretend
  it is.
* WebRTC discloses IP candidates to the other side of the room, as it always
  does; a TURN server would hide them, and none is configured by default.
