# Task: do-duration-budget

- **Name:** do-duration-budget
- **Priority:** P1
- **Area:** kant-zk, relay, cloudflare, cost
- **Status:** open — spec gap, confirmed against live docs
- **Created:** 2026-10-03
- **Related:** PB-19, `2026-10-03-websocket-hibernation-bug`
- **Tags:** kant-zk, relay, cloudflare, cost, budget

## The gap

Spec §12.1 gives a free-tier budget table. Every row in it matches current
Cloudflare documentation except one: **Durable Object duration, 13,000 GB-s per
day**, is missing. That is the row PB-19 actually exhausted. The error text
was literal: `Exceeded allowed duration in Durable Objects free tier`.

A budget table that omits the limit you hit is not a budget table. §16 alerting
inherits the omission, so the spec currently asks for alerts on metrics that
cannot have caused the incident it was written to prevent.

## Free tier, as documented

| Resource | Free tier per day |
|---|---|
| Requests | 100,000 |
| **Duration (GB-s)** | **13,000** ← missing from §12.1 |
| SQLite rows read | 5,000,000 |
| SQLite rows written | 100,000 |
| Storage | 5 GB |

Duration is `GB-seconds = wall-clock seconds held × instance size in GB`. A
1 GB instance held for one hour costs 3,600 GB-s. There is no per-request
discount and no free partial day: the budget is consumed continuously and
resets at midnight UTC.

## Why the earlier fix worked and why it is not enough

PB-19's cure was client-side pacing: the long poll capped at a third of the
period, exponential backoff with jitter, a latched quota window. It took
requests from 1847 in 12 seconds down to 2 per 12 seconds, which is the right
result. But pacing reduces *how often* rooms are held; it does not make a held
room free. At a 60s period with a 20s long poll the duty cycle is ~33%, and
four rooms at 128 MB each is roughly 1,880 GB-s/day — 14% of the tier for one
room's worth of chat. It scales linearly with rooms. Ten rooms exhausts it.

The durable answer is hibernation, which is exactly what
`2026-10-03-websocket-hibernation-bug` is about. Until that call site is
fixed, every GB-s in the table above is billed regardless of idleness.

## What to add

1. **§12.1**: add the duration row, with the arithmetic spelled out rather than
   just the number, so the next reader can check a duty cycle against it.
2. **A per-room cost line.** Make it derivable: `duty × 86,400 × rooms × size
   GB`, with a worked example. PB-19's own failure was a mis-modelled number —
   10s period with a 10s long poll is a 100% duty cycle, which nobody wrote
   down.
3. **§16 alerting**: alert on projected *daily* duration from observed duty
   cycle, not on instantaneous or request-based signals. The signal to watch
   is `sum over rooms of (held seconds) / wall-clock seconds`, and it should
   alert at 50% of the daily budget, which is roughly 6,500 GB-s.
4. **A room cap.** Once duration is a modeled quantity, decide what the maximum
   concurrent-room count is on the free tier and enforce it. This is the
   decision PB-19 never made, and the reason it could recur.

## Arithmetic to record

```
projected_GBs_per_day = duty_cycle × 86400 × rooms × size_GB
duty_cycle            = (poll_period_hold / poll_period)   # long poll over full period
```

At 60s period / 20s hold / 4 rooms / 0.128 GB: 0.333 × 86400 × 4 × 0.128 =
14,745 GB-s/day → **over budget**. Hibernation-corrected (duty → ~0 when
idle) the same configuration sits near zero and is a non-event.

## Note on supersession

This budget assumes Durable Objects exist. It is the arithmetic that the
same-day "remove all DO" decision avoided — by removing the stateful layer
entirely and paying with cross-PoP correctness instead. Now that §19 puts
Durable Objects back, this table has to exist and be enforced. It is the
cheapest of the four federated tasks and the one that most directly prevents a
recurrence of a real incident.
