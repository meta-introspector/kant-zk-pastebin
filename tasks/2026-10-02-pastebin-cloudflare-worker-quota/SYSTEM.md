# pastebin-cloudflare-worker-quota-exhausted
- **Priority:** P2
- **Tags:** budget

**Status:** **done** 2026-10-03 — commit `6604d52` in pastebin-lean.
Root cause was three separate things, not one. · **Date:** 2026-10-02

## Root cause (2026-10-03)

The free tier bills Durable Object **duration**, not requests. Three
things followed from that, and only the first was obvious:

1. **The healthy case was the expensive one.** `--interval 10` with a
   hardcoded `wait: 10` means each room is held open ~100% of the time —
   four rooms, permanently. Nothing had to fail for this to drain the
   budget.
2. **The error path cost the same as success.** `pump()` slept a flat
   `fwd.interval` after *any* error, so the 2056 failures in the journal
   each bought exactly as much duration as a healthy poll.
3. **The quota error was undetectable.** `RelayClient.request` threw
   `` `relay ${what} failed: ${r.status}` `` and discarded the body. The
   worker says "Exceeded allowed duration in Durable Objects free tier"
   in the *body*; the client threw away the only sentence that said so,
   making this indistinguishable from a transient 500.

## The fix

- `server/backoff.mjs` — exponential with equal jitter, reset on success,
  capped at `--max-interval`. The free-tier message is classified
  separately and **latched**: retrying cannot succeed until the daily
  budget resets, so it sits out a full quota window rather than asking
  again in 10s.
- `holdFor()` — the long poll can never exceed a third of the period, so
  "every 60s" is actually true. Default interval 10s → 60s.
- `RelayClient` now includes the relay's own error body in the message
  and sets `err.status`.

Live unit now runs `--interval 60 --wait 10 --max-interval 900`.

## Two bugs found while proving it

**`--rooms --once` did nothing.** `scan()` fired `runBridge` without
awaiting and then called `process.exit(0)`, so it listed the rooms it
found and exited having contacted no relay. My earlier `--once`
verification missed this because I checked the log lines, not whether any
work happened.

**Seconds vs milliseconds — a hot loop, not a backoff.** `Backoff` works
in ms; the CLI works in seconds. Passing the CLI value straight through
made `--interval 10` a **10ms** backoff, growing 10 → 20 → 40ms and
capping at 900ms: **1847 requests in 12s** against a refusing relay,
far worse than the flat sleep it replaced. Every unit test passed the
whole time, because the arithmetic was right and the wiring was not. The
end-to-end test that counts actual requests is what caught it. Fixed by
converting once, in `Bridge`.

## Verification

`server/backoff-test.mjs` (17) and `server/forward-backoff-e2e.mjs` (6),
plus the existing suites unchanged: net 32, flow 85, join 14, codec 91,
diag 68, cli 77, site 53, handpage 32, qr 15, sharelog 64, pastebin 16,
file 12, uucp 28, pair 5, disk-blocks 5.

Deployed and re-enabled: 150s with 0 failures, 0 restarts, **2 requests
in 12s** where the broken version made 1847.

## Traps

- `ProtectHome=true` cannot be used on this unit. The checkout is under
  `/home/mdupont/projects/pastebin-lean` (a symlink into `/mnt`), so it
  fails at `CHDIR` with `status=200/CHDIR`. The versioned unit file
  carried that hardening block and had drifted from the installed one;
  copying it over broke the service until the block came out.
- `StartLimitIntervalSec` / `StartLimitBurst` belong in `[Unit]`, not
  `[Service]`. `systemd-analyze verify` catches it.
- `/health` on this worker touches no Durable Object, so it cannot detect
  budget exhaustion. `relayUsable` (PB-17) inherits that limit: health
  proves the process is up, not that its storage is reachable.

## Options if the budget is still too tight

1. Move the Worker to a paid Durable Objects plan.
2. Second Worker on a paid account; point `--default-to` at it.
3. Raise `--interval` further, or drop the long poll (`--wait 0`).

## Symptom

`kant-relay-v1.purple-fire-b881.workers.dev` answers health and fails
everything else:

    GET  /health   200  {"ok":true,"name":"kant-zk-relay","version":"1.0.0","platform":"cloudflare"}
    GET  /room/…   500  {"ok":false,"error":"Exceeded allowed duration in Durable Objects free tier."}
    POST /room/…   500  (same)

Every room, not one — tested on the room from a real invite and on a freshly
invented one. `wait=0,1,2,5` all fail identically, so it is not the long-poll.
The error names the cause: the Durable Objects free tier's daily duration
budget.

## Blast radius

`kant-zk-forward.service` defaults to this worker:

    node server/forward.mjs --rooms /var/lib/kant-zk/rooms \
      --default-from https://solana.solfunmeme.com/relay \
      --default-to  https://kant-relay-v1.purple-fire-b881.workers.dev

It has logged `relay poll from 0 failed: 500` every 10 seconds since
**17:38 today**, and has succeeded zero times since 2026-10-02. Over two days:

| status | count | meaning |
|--------|-------|---------|
| 429 | 1104 | rate limited |
| 500 | 770  | free-tier duration exhausted |
| 404 | 765  | room not found there |
| 502 | 14   | upstream |

Note the 429s: the forwarder is itself burning quota by polling every 10s,
which likely contributes to the exhaustion. Backoff would help both.

## Why it looks healthy

`/health` does not touch the Durable Object, so it stays 200 while all room
traffic fails. A client that probes only health concludes the relay is up. This
is the limit of the `relayUsable` check added in PB-17: health proves the
relay process is up, not that *this* client can reach *this* relay's storage.

A browser opening a real invite on that relay showed the full false-healthy
sequence:

    transport: "Relay …workers.dev is up — other devices can join."
    joinmsg:   "joined room bcdcffa6b8d8…"      (room is derived locally)
    network:   500 POST /room/bcdcffa6…, 500 GET /room/bcdcffa6…

## Options if the budget is still too tight

Listed under Root cause above; the bridge is no longer the thing draining
it, so these are about the tier, not the client.
