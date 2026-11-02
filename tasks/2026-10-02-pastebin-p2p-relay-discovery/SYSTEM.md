# pastebin-p2p-relay-discovery
- **Priority:** P2
- **Tags:** 2026-10-02-pastebin-p2p

**Status:** done (deployed and verified) · **Date:** 2026-10-02

## What was broken

The chat at `https://solana.solfunmeme.com/p2p-relay/` could not find the
relay that was serving it. Two independent causes, both silent.

**1. The page probed the wrong base.** `refreshTransport` passed
`location.origin`, so the client asked `https://solana.solfunmeme.com/health`.
The relay is mounted at `/p2p-relay/` and answers `/p2p-relay/health` — 200,
`{"ok":true,"name":"kant-zk-relay",...}`. The bare origin 404s, and a failed
probe only downgrades a banner, so nothing looked broken.

**2. A dead configured relay beat the working one.** `kant.config` named
`relay = https://kant-relay.cicada71.net`, which does not resolve (NXDOMAIN).
`resolveReachability` returns as soon as a relay is *configured*, so that dead
name won over the working origin every time.

## The fixes

- `web/kant-diag.mjs`: new `servedBase(href)` — the directory the page was
  served from. Equals the bare origin when the relay serves at the root, and
  carries the mount prefix when it does not.
- `web/index.html`: `refreshTransport` uses `D.servedBase(location.href)`.
- `web/kant.config`: `relay =` left empty, with the reason in a comment.

## A third bug the control run exposed

Running the *fixed* page next to the *pre-fix* page in a browser showed the old
one printing:

    Relay https://kant-relay.cicada71.net is up — other devices can join.

over a host that does not resolve. `effectiveRelay` hands back a configured
relay whether or not the probe found it — that is the spec, since preferring
the operator's choice is correct — but the banner chose its wording from that
value. It now reads `relayUsable`, which is what records whether the relay
answered. `effectiveRelay` still decides what the client talks to.

## Verification

- `web/diag-test.mjs`: 68 -> 79. Unit cases for `servedBase` (root, sub-path,
  file dropped, query/hash, no-trailing-slash-means-a-file, junk input), a
  live case that derives the base the way the page does, and a case pinning
  the configured-but-dead pair the banner must not confuse.
- Local relay in Chromium, both mount shapes, plus a prefix-stripping proxy
  reproducing the nginx rewrite: 6/6.
- **Live, public:** two isolated browser contexts (no shared
  BroadcastChannel) at `https://solana.solfunmeme.com/p2p-relay/index.html`.
  A started a room, B opened the 232-char invite, A sent a line, B received
  it. 7/7. The relay log shows the `POST /room/{id}` and the long-poll
  `GET` that carried it.

## Deployed

Cherry-picked onto `feature/big-merge` (the branch `:8796` serves), which is
what `https://solana.solfunmeme.com/p2p-relay/` actually runs:

- `659f2a12` fix(p2p): find the relay that served this page, not the bare origin
- `2b35ce55` fix(p2p): stop the banner announcing a dead relay as up

`sudo systemctl restart kant-p2p-relay.service`. Both also on
`feat/cli-fileshare` (`60062e88`, `f9c71ac2`) and pushed.

## Worth knowing

An invite is a **fragment**, read once at startup. Opening one in a tab that is
already on the app URL is a same-document navigation: no reload, no re-read, no
join. Real people open an invite in a new tab, so this is not a defect — but
any test that drives two pages must give the second one a fresh page, or it
will look like a join failure.

## Not done here

PB-2 still stands: `kant-p2p-relay.conf` publishes this URL and exists only
on disk, unmanaged. A profile rebuild loses the chat.

## Update (2026-10-03)

The p2p surface moved forward in the integration session: pastebin-lean
`main` is now `bbac0ab` and carries the buffy p2p-wasm webapp
(`web/p2p.html`, `kant-p2p.mjs`, `kant-ipfs.mjs`, proved-kernel wasm
experiments, merge `594609b`) plus the hermetic p2p test fix (`bbac0ab`:
`P2PApp.publish` passes `rpcBase`/`gwBase` through; test pins dead port
`http://127.0.0.1:1` because a live kubo runs on 127.0.0.1:5001 on this
host). 19 test suites green. See task
`2026-10-02-pastebin-lean-arist-integration`. PB-2 (unmanaged nginx conf)
remains open.
