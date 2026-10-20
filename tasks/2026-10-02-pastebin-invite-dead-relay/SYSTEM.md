# pastebin-invite-dead-relay

**Status:** fixed on `feat/cli-fileshare` (`18896c83`, pushed) — **not yet deployed**
**Date:** 2026-10-02
**Related:** PB-17 (p2p relay discovery, fixed and deployed)

## The bug

An invite carries a relay in its payload, and `joinInvite` uses it
**unconditionally**:

    web/kant-net.mjs:848-851
      if (i.relay) {
        this.relayBase = i.relay;
        this.client = new RelayClient(i.relay, ...);

So an invite minted while the deployment named a dead relay keeps sending
every joiner to that dead relay — even when the page is being served by a
working one that has the same room.

## Reproduced live

Invite (from the operator, valid `kzinvite`):

    relay https://kant-relay.cicada71.net   ← NXDOMAIN
    peer  peer-kp49w
    room  eed8a6c3671a9041f099170cb3aa6f5ae53db0d8c619d22f08ce895935fb7f00

Opened at `https://solana.solfunmeme.com/p2p-relay/` — served by a working
relay. In the browser:

    transport: This page is served by a relay (https://solana.solfunmeme.com/p2p-relay) …
    joinmsg:   "joined room eed8a6c3671a…"          ← true; room is derived locally
    network:   504 POST https://kant-relay-cicada71.net/room/eed8a6c3…
               504 GET  https://kant-relay-cicada71.net/room/eed8a6c3…

The banner is about the page's own relay; the client is talking to a different,
dead one. Nothing warns. Same room, two relays:

    serving relay  GET /room/eed8a6c3…  200  {"ok":true,"cursor":0,"lines":[]}
    invite relay   GET /room/eed8a6c3…  000  (DNS does not resolve)

## Why it is a decision, not just a patch

Silently ignoring the invite's relay would break the case the relay field
exists for: two peers on *different* relays, where only the invite can tell
the joiner where to go. Trusting it unconditionally is what strands people
today.

The defensible middle: probe the invite's relay, and **if it does not answer,
fall back to the relay that served the page — and say so**. Same shape as
`effectiveRelay`/`relayUsable` in PB-17. That needs a decision on whether to
surface it loudly, since a room on the wrong relay is not the same room: a
silent fallback could put two people in rooms that look identical and are not.

## Third silent-failure variant

Three now, all the same shape — a status that reads healthy while the
transport underneath is dead:

1. PB-17: probed `location.origin`, got a 404 for a relay mounted at a prefix.
2. PB-17: banner read `effectiveRelay`, called a dead configured relay "up".
3. **This:** the invite's relay is used without being probed at all.

And a limit of the PB-17 fix, worth recording: `relayUsable` would **not**
catch case 3, because the page's own `/health` genuinely answers 200. Health
proves the relay process is up; it does not prove *this* relay is reachable
*from this client* for room traffic. The Worker in PB-18 fails exactly this
way — `/health` 200, every `/room/…` 500.

## Invites minted now are fine

Since the servedBase fix, the share screen builds the link from the relay that
is actually serving the page:

    invite relay: https://solana.solfunmeme.com/p2p-relay

Verified 7/7 with two isolated browser contexts: A hosts, B opens the invite,
A sends, B receives. So this only affects invites minted **before** the fix,
and any peer still naming `kant-relay.cicada71.net` — the same dead host that
was in `kant.config`. Those old invites cannot be repaired; they have to be
reminted.

## The fix

`KantNode.settleRelay({ fallback, timeoutMs })`, run after `joinInvite` and
before `attach`:

- probe the relay the invite named;
- if it answers, use it — the cross-relay case the field exists for;
- if it does not and there is a fallback, switch to the fallback, rebuild the
  client, and log at `error` naming the relay it gave up on;
- if it does not and there is no fallback, keep it and log — nowhere else to
  go, and pretending otherwise helps nobody.

Kept separate from `joinInvite` because that is synchronous with eight callers
that must stay so. `joinFrom` became async as a result, so the startup join is
awaited (rendering before it settles would paint a room that is not attached
yet) and the camera scan clears `camera` before awaiting rather than racing a
second join.

## Verified

`web/join-test.mjs` 14 -> 29, against the real `server/relay.mjs`:

- an unprobed invite does point at the dead relay — the bug, stated first
- dead relay + no fallback: kept, logged
- dead relay + fallback: switched, client rebuilt, error logged naming the old one
- **the line actually crosses after falling back** — a fallback that leaves
  people in a dead room is worse than no fallback
- a working invite relay is never overridden
- the same relay twice is a no-op
- an invite with no relay and no fallback goes nowhere

And in a real browser against a local relay, with an invite deliberately
poisoned to name a dead relay: 7/7. The join message reads

    joined room a2a0603e7546… — but the relay this invitation names
    (http://127.0.0.1:1) did not answer, so this is not the room the sender
    is in. Ask them to send a fresh invitation.

in the `.bad` warning colour, and the line crosses afterwards.

## Not deployed

The deployment checkout `/home/mdupont/projects/pastebin` has an unrelated
merge in progress (`origin/fix/mesh-state-methods` into `feature/big-merge`,
started 19:41, with `src/handlers.rs` and `src/model.rs` both `UU` and
conflict markers in the tree). The operator is resolving that first. The
working copy there holds the same three files edited but uncommitted; they are
backed up at `/tmp/settle-relay-web.patch` and as individual `.bak` copies.
