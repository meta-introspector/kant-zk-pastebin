# "Two cards, and they are not connecting"

Two blocks of text were reported as two cards that would not connect:

```
kant-zk-pastebin
https://kant.cicada71.net/#ff810f291f187b808a0183f83c0466874573ef5c4c6d7d9ed430c6f7d710f605
6b7a63617264:68747470733a2f2f6b616e742e63696361646137312e6e65742f2366663831…:6b616e742d7a6b2d706173746562696e:2e2f6b616e742d6c6f676f2e737667:746865204b616e7420706173746562696e206c6f676f
```

…twice, and the report added: *I cannot figure out the system, there is no
log I can find.*

There are two separate findings, and a third about the log.

## 1. Those are not two things. They are one card, twice — and a card cannot connect

Decode the third line (`6b7a63617264` is `kzcard`) and you get, in both
blocks, exactly:

| field | value |
|---|---|
| url | `https://kant.cicada71.net/#ff810f291f187b808a0183f83c0466874573ef5c4c6d7d9ed430c6f7d710f605` |
| caption | `kant-zk-pastebin` |
| picture | `./kant-logo.svg` |
| alt | `the Kant pastebin logo` |

The two blocks are byte-identical, so they are the same object: one page,
shared twice. Proved: `Kant.CardDebug.userCard_classify`.

More importantly, **a card is not a connection at all.** This system issues
three different codes and they are not interchangeable:

| code | carries | can it connect two clients? |
|---|---|---|
| `kzcard:…` | a page URL, a caption, a picture | **no** — it names no room |
| page link `<origin>#<64 hex>` | a content address | **no** — it names no room |
| `kzinvite:…` | a relay and a secret whose digest is the room | **yes** |

`Kant.CardDebug.card_no_room` and `page_no_room` say a card and a page link
name no room; `pair_not_connectable_of_card_left` / `…_right` and
`pair_not_connectable_of_page_left` say that pairing one with anything is
never `connectable`; `userCard_not_connectable` says it of this exact text.
`pair_connectable_iff` says what does work: **two invitations, the same
room, and one and the same non-empty relay** — and `connectable_linked`
proves that such a pair really does put two clients in touch, in the sense
of `Kant.Connectivity.Linked`.

So: nothing was broken in the connecting machinery, because nothing ever
asked it to connect. To connect, use **Share → Invite someone to chat** on
one device and let the other scan or paste that `kzinvite` code.

## 2. …and even a correct invitation cannot connect two devices on this deployment

Checked against the live site on 2026-09-03:

```
GET https://kant.cicada71.net/          200  (the current build: it has the Diagnostics card)
GET https://kant.cicada71.net/kant.config  200  → `relay =` (blank)
GET https://kant.cicada71.net/health    404
GET https://kant.cicada71.net/room/<room>  404
```

The origin is a plain static host: it serves the page, but it is not a
relay. With `relay =` blank and the origin not answering `/health`,
`Kant.Connectivity.effectiveRelay` is empty — there is **no meeting point at
all** (`effectiveRelay_needs_probe`). Two tabs of one browser still find
each other over `BroadcastChannel`, but two devices, or two different
browsers, provably cannot exchange anything, however correct the invite:
`Kant.CardDebug.static_deployment_stuck`.

The fix is one line, and it is proved to be enough
(`Kant.CardDebug.configured_relay_links`): in `web/kant.config`, set

```
relay = https://relay.kant.cicada71.net
```

pointing at a deployed `server/relay.mjs` or `server/worker.js`, and
redeploy. Locally, `node server/relay.mjs --port 8787 --static web` makes
the origin itself a relay and needs no configuration at all.

Reproduce the check here:

```
node scripts/kant-debug.mjs --probe
```

## 3. Where the log is

There is no server-side log because, on a static host, there is no server in
the conversation. The run log is on your own machine, in three places:

1. **The Diagnostics card** at the bottom of `index.html` — the live tail of
   the current run, with *Copy the whole run*, *Save the run as a file* and
   *Open the diagnostics page*. It is kept in `localStorage`, so the run from
   before the last reload survives.
2. **`diag.html`** — the whole run as a table, *Run the checks on this
   machine*, a copyable link that carries the run in its fragment, *Load the
   run from before the last reload*, and now **What is this code?** (below).
   It is deployed: <https://kant.cicada71.net/diag.html>.
3. **The relay**, if you run one: `node server/relay.mjs --log relay.log`
   writes every request, refusal and socket event.

## What was added for this

- **`RequestProject/Kant/CardDebug.lean`** — the specification and the
  proofs: `classify` (which of the three codes is this?), `pair` (what
  happens when two are held up against each other), the theorems above,
  `explain_injective` (six outcomes, six different sentences), and the
  report's own text run through the classifier. Golden `#guard` vectors at
  the end are shared with the JavaScript.
- **`web/kant-carddebug.mjs`** — the same rules in the client.
- **`web/diag.html` → "What is this code?"** — paste one code, or two, and
  it says what each is, whether they can connect, and what to do instead.
- **`scripts/kant-debug.mjs`** — the same from the command line:

  ```
  node scripts/kant-debug.mjs "<first code>" "<second code>"
  node scripts/kant-debug.mjs --probe
  node scripts/kant-debug.mjs --where-is-the-log
  ```

  On the reported text it prints:

  ```
  verdict: same-code
  same-code: both pastes are the same code, so there are not two things here to
  connect; ask the other side for their own invite
  ```

- **`web/carddebug-test.mjs`** — 73 checks, including the reported blocks and
  the invitation vectors Lean pins.

## A smaller thing, while we were in there

The card's `picture` is `./kant-logo.svg`, a relative reference. On the site
it resolves; in a card pasted into a chat window, an issue tracker or another
host, it does not. `cardWarnings` reports this as `relative-picture`
(`Kant.CardDebug.userCard_warnings`). Set `picture =` in `kant.config` to a
full `https://…` URL or a `data:` URI if cards are meant to travel.
