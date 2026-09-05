# The guided flow: one link, one code, a camera you can switch off

This is the design of `web/index.html`, the simple client.  Everything the page
does is a transcription of `web/kant-flow.mjs`, which is itself a transcription
of four Lean modules; those modules are where the claims below are actually
proved.

| Lean module | what it fixes | the complaint it answers |
|---|---|---|
| `RequestProject/Kant/InviteCard.lean` | the code carries the whole link, with a custom icon and a custom line of text | *"the QR code did not show the link, only `6b7a…`"* |
| `RequestProject/Kant/Join.lean` | a pasted link is found however it arrives | *"the join link does not join the room"* |
| `RequestProject/Kant/Onboarding.lean` | screens, the camera switch, the guided first run | *"the camera cannot be turned off; the interface is confusing"* |
| `RequestProject/Kant/PlainText.lean` | copying gives the text, details optional | *"copying a paste yields encoded text"* |

The JavaScript is checked against those statements by `node web/flow-test.mjs`.

---

## 1. What was wrong with the old code

The share code used to carry the bare envelope:

```
6b7a696e76697465:68747470733a2f2f6b616e742e63696361646137312e6e6574:05a3…:706565722d333861336b
```

A phone camera reads that and offers nothing: it is not a URL, so there is no
"open" button, and a human who reads it out loud learns nothing.  What the code
carries now is the whole page link:

```
https://kant.cicada71.net/#6b7a696e76697465:68747470733a2f2f…:05a3…:706565722d333861336b
```

`Kant.InviteCard.inviteUrl_origin_prefix` says the payload begins with the
configured origin; `inviteUrl_not_bare` says that as soon as the origin is
non-empty the code is *not* the bare envelope any more;
`parseInviteUrl_inviteUrl` says scanning it still recovers exactly the
invitation, and `inviteUrl_fits_qr` says the longer payload still fits in one
code.

Around the code sits a card: the icon drawn in the middle
(`inviteCardSvg_icon_used`), the chosen line of text under it
(`inviteCardSvg_caption_visible`), and the link itself printed underneath
(`inviteCardSvg_url_visible`), so a card photographed or forwarded is still
readable by a human.  The icon covers at most a twenty-fifth of the modules
(`inviteCard_icon_area_bound`), inside the error-correction budget, so drawing
on the code does not stop it scanning.  Nothing typed into the caption or the
icon box can break out of its SVG element (`inviteCard_no_markup`), and the
exported picture still carries the card in a comment, so it reads back whole
(`readCard_inviteCardSvg`, `inviteCardSvg_roundTrip`).

Both the caption and the icon are editable on the share screen: the defaults
come from `caption =` and `picture =` in `web/kant.config`.

The same card can be made from the command line, from a bare code, a link, or a
whole message with one in it:

```
node scripts/invite-card.mjs '6b7a696e76697465:6874747073…:05a32f7c…:706565722d333861336b' \
  --caption 'join my kant room' --icon ./kant-logo.svg --out invite-card.svg
```

It prints the room, the link the code now carries, and refuses to write a card
that does not read back as the invitation it was made from.

## 2. Use cases

```
                        ┌──────────────────────────────────────────┐
                        │            Kant simple client            │
                        │                                          │
   ┌────────┐           │   (Start a room)                         │
   │        │───────────┼──▶                                       │
   │ Host   │           │   (Show the one link and the one code)   │
   │        │───────────┼──▶        ▲                              │
   └────────┘           │           │ «include»                    │
        │               │   (Dress the code: icon + words)         │
        │               │                                          │
        │               │   (Say something in the room)            │
        └───────────────┼──▶                                       │
                        │                                          │
   ┌────────┐           │   (Paste a link)  ──«extend»──▶ (Scan a  │
   │        │───────────┼──▶                               code)   │
   │ Guest  │           │           ▲                        │     │
   │        │           │           │ «include»              │     │
   └────────┘           │   (Find the invite in the text) ◀──┘     │
        │               │                                          │
        │               │   (Copy a note as readable text)         │
        └───────────────┼──▶        ▲                              │
                        │           │ «extend»                     │
                        │   (…with its title, link, address, time) │
                        │                                          │
                        │   (Stop the camera)   ← always available │
                        └──────────────────────────────────────────┘
                                     │
                              «uses» ▼
                        ┌──────────────────────────┐
                        │  Relay (least trusted)   │
                        │  server/relay.mjs        │
                        └──────────────────────────┘
```

## 3. The screens

Six, and no more.  `Kant.Onboarding.Screen`.

```
        ┌──────────────────────────── back ────────────────────────────┐
        │                                                              │
        ▼                                                              │
   ┌─────────┐  Start a room   ┌────────┐  Open the room  ┌────────┐   │
   │ welcome │────────────────▶│ share  │────────────────▶│  chat  │───┤
   │         │                 │        │◀────────────────│        │   │
   │         │  Join a link    └────────┘  Show the link  └────────┘   │
   │         │────────────────▶┌────────┐                     ▲        │
   │         │                 │  join  │─── link found ──────┘        │
   │         │  Scan a code    └────────┘                              │
   │         │────────────────▶┌────────┐                              │
   │         │                 │  scan  │─── code read ───────────────▶│
   │         │  More           └────────┘                              │
   │         │────────────────▶┌────────┐                              │
   └─────────┘                 │  more  │──────────────────────────────┘
                               └────────┘
```

`back_goes_home` — the back button always lands on `welcome`, from anywhere.
`screen_reachable` — every screen is one tap from the first one.

### The camera

The old page started the camera from a button and offered no way to stop it.
Now the camera is a field of the state, and it is switched off by *five*
different things, each proved:

| event | theorem |
|---|---|
| the **Stop the camera** button | `camera_off_after_stop` |
| the back button | `camera_off_after_back` |
| leaving the room | `camera_off_after_leave` |
| tapping through to any screen but `scan` | `camera_off_after_goto` |
| a code actually being read | `camera_off_after_join` |

and the invariant that makes that a guarantee rather than a list:

> `camera_implies_scan` — in **every** state the interface can reach, if the
> camera is running then the screen on show is the scan screen.

So the stop button is always in front of the user; the camera can never be left
running behind another screen.  `web/flow-test.mjs` re-checks this
exhaustively over every state reachable in three events.

## 4. Joining, however the link arrives

The old join box did nothing but `.trim()`.  Measured against the real thing, it
refused a link with a trailing newline, a link with a full stop after it, a link
in `<angle brackets>`, and a code with a newline — all of which are exactly what
a chat client hands you when you copy a message.

`Kant.Join.findInvite` cuts the pasted text into words at any whitespace, and for
each word takes everything after the last `#`, trims from both ends anything that
cannot occur inside a code, and tries to read that.  Proved:

- `findInvite_inviteUrl` — the link from the share screen is found;
- `findInvite_copyInvite` — so is the bare code, for anybody still passing those;
- `findInvite_in_message` — so is a link with any junk-free words around it;
- `findInvite_trailing_newline` — so is a link with a newline after it;
- `wordInvite_junk` — a word that is not a code is never mistaken for one;
- `message_same_room` — and both sides end up in the *same* room.

### Sequence: host and guest meet

```
 Host                 Client A            Relay            Client B              Guest
  │                      │                  │                  │                   │
  │ Start a room         │                  │                  │                   │
  │─────────────────────▶│                  │                  │                   │
  │                      │ freshSecret; room = witness(secret) │                   │
  │                      │ GET /health ────▶│                  │                   │
  │                      │◀──── { ok } ─────│                  │                   │
  │  link + dressed code │                  │                  │                   │
  │◀─────────────────────│                  │                  │                   │
  │                                                                                │
  │  https://…/#kzinvite:…   (chat message, or a photo of the code)                │
  │═══════════════════════════════════════════════════════════════════════════════▶│
  │                      │                  │                  │  paste / scan     │
  │                      │                  │                  │◀──────────────────│
  │                      │                  │                  │ findInvite(text)  │
  │                      │                  │                  │ room = witness(secret)
  │                      │                  │◀─ POST /room/{room}  kzpeer …        │
  │                      │◀ GET /room/{room}?cursor=N ─────────┤                   │
  │                      │  kzsig offer ───▶│─────────────────▶│                   │
  │                      │◀─────────────────│◀─ kzsig answer ──│                   │
  │                      │◀════════ direct WebRTC data channel ═══════════════════▶│
  │  message             │                  │                  │                   │
  │─────────────────────▶│═════════════════════════════════════▶│  message         │
  │                      │                  │                  │──────────────────▶│
```

The relay only ever carries opaque lines.  It learns the room (a hash of the
secret) and never the secret itself, and it cannot forge a message: every line
is checked against its own witness on arrival (`Kant.Relay.relay_cannot_forge`,
`Kant.Rendezvous.scan_same_room`).

## 5. Why two devices did not find each other

Two *tabs* of one browser always worked, because they share a
`BroadcastChannel` — no server involved.  Two *devices* need something both can
reach, and the old page pointed the relay at `location.origin`.  On a static
host there is no `/health` and no `/room/{room}` there, so every relay request
failed, and every failure was swallowed silently.  The page looked fine and
nothing arrived.

Three changes:

1. **The relay is configured, not guessed.**  `relay = …` in `web/kant.config`.
2. **The relay is probed, visibly.**  On startup the client calls `/health` and
   says on the first screen what it found.  With no relay configured it says so
   in as many words — *"two tabs of this browser will find each other, but a
   link opened on another device will not"* — rather than pretending.
3. **The invite carries the relay absolutely.**  The guest's client takes the
   relay out of the invitation (`KantNode.joinInvite`), so the two sides use the
   same one even when they are served from different places.

To make cross-device joining work, deploy a relay and name it:

```
# web/kant.config
relay = https://relay.kant.cicada71.net
```

`server/README.md` has the two deployments — `server/relay.mjs` for any Node
box, `server/worker.js` for Cloudflare Workers — and the four-line protocol they
implement.

## 6. The guided first run

Three tasks, in order, and none of them can be un-done
(`Kant.Onboarding.step_progress_mono`):

| task | screen | what the guide says |
|---|---|---|
| `getIn` | `welcome` | *"Step one of three. Tap Start a room to make a new room, or tap Join and paste the link somebody sent you."* |
| `shareIt` | `share` | *"Step two of three. This is your link and your code. Copy the link into any chat, or let the other person point their camera at the code."* |
| `sayHello` | `chat` | *"Step three of three. Type a line and send it. Everyone who followed your link sees it."* |

and when they are done, *"That is everything. You have a room, you have shared
it, and you have said something in it."*

The guide is spoken aloud through the browser's speech synthesis and printed in
the green band at the top; the speaker button silences it.  `hushed_says_nothing`
— with the voice hushed, what is spoken is the empty string, exactly.
`promptFor_ne_empty` — with it on, there is always a line to say.
`nextTask_eq_none_iff` — the guide stops exactly when all three are done, no
sooner and no later.  `nextTask_screen` sends each task to the screen it is done
on.

Two scripted runs are proved to finish:

- `first_run_completes`: start a room, copy the link, say something.
- `join_run_completes`: follow somebody's link, copy the link, say something —
  and it leaves you in a room, on the chat screen, with the camera off.

## 7. Copying a note as text

`Kant.PlainText`.  `copyPlain_eq_content` — what is copied is the characters of
the note, not an encoding of them; `copyPlain_ne_copyText` — as soon as the text
contains one character a code cannot contain (a space, a full stop, a capital
letter) the plain copy and the envelope genuinely differ.

The details are optional.  **Copy the text + details** produces

```
The Critique of Pure Paste
-- 
title: a note
link: https://kant.cicada71.net/#ff810f29…
address: ff810f29…
posted: 20260902000000
```

and that is separable again: `bodyOf_copyPlainWithMeta` gives back exactly the
text that was typed, `metaOf_copyPlainWithMeta` gives back exactly the four
details, and `copyPlainWithMeta_link_visible` says the whole page link really is
printed in the footer.  The one caveat, and it is in the statement: the text
must not itself contain a line that is exactly `-- `.

## 8. Where the old page went

Nothing was removed.  The full control panel — the pastebin, framing under the
5 MB cap, stego PNGs and SVGs and WebM, pinning and credits, the sneakernet, the
code movies, the wasm kernel — is now `web/lab.html`, reachable from **More →
Open the workbench**.  It gained the two plain-text copy buttons as well.
