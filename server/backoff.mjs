// backoff.mjs — how long the relay bridge waits before trying again.
//
// The bridge is a client of two relays, one of which may be a Durable
// Object on Cloudflare's free tier.  That tier bills *wall-clock storage
// duration*, not requests, so two things drain it:
//
//   1. long-polling.  A `--wait N` poll holds the room's DO alive for up
//      to N seconds.  At `--interval 10 --wait 10` the bridge holds four
//      rooms open essentially forever — a ~100% duty cycle, which is the
//      normal state, not a failure.  So the *steady-state* cadence
//      matters more than the error path.
//   2. the error path.  A relay answering 500 every 10s spends the same
//      budget as a healthy one and never gets better for trying, because
//      nothing told it to wait longer.
//
// So: a poll period (`--interval`) that is deliberately longer than the
// long-poll hold, and exponential backoff with jitter on failure, with a
// hard floor for the specific error that means "you have run out of
// budget today" — hammering through that cannot succeed until the
// budget resets, so the only correct response is to stop asking.

export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** Pull a status code and a kind out of whatever RelayClient threw.
 *  RelayClient's errors carry the status in the message text; a `status`
 *  property is used too when present, so this keeps working if that
 *  message ever changes shape. */
export function classify(err) {
  const msg = String(err?.message ?? err);
  const status =
    Number(err?.status) || Number(msg.match(/failed:\s*(\d{3})/)?.[1]) || 0;
  const body = msg.toLowerCase();
  if (/exceeded allowed duration|durable objects free tier/.test(body))
    return { kind: "quota", status };
  if (status === 429) return { kind: "rate", status };
  if (status >= 500) return { kind: "server", status };
  if (status === 404) return { kind: "missing", status };
  if (
    /could not reach|timed out|fetch failed|econnrefused|etimedout|enotfound|eai_again/.test(
      body,
    )
  )
    return { kind: "network", status };
  return { kind: "other", status };
}

/** Retry pacing for one loop.  Success resets it; failure grows it.
 *
 *  All durations here are MILLISECONDS.  The command line is in seconds,
 *  so the conversion happens once, where the bridge reads its args —
 *  passing seconds into this class silently turns a 10s backoff into a
 *  10ms one, which is a hot loop rather than a backoff. */
export class Backoff {
  constructor({
    base = 60_000,
    cap = 900_000,
    quotaFloor = 900_000,
    jitter = 0.5,
    rand = Math.random,
  } = {}) {
    this.base = Math.max(1, Number(base) || 60);
    this.cap = Math.max(this.base, Number(cap) || 900);
    this.quotaFloor = Math.max(this.base, Number(quotaFloor) || 900);
    this.jitter = Math.min(1, Math.max(0, Number(jitter)));
    this.rand = rand;
    this.failures = 0;
    this.quota = false;
  }

  /** A poll came back.  The next attempt is a plain `base` away again. */
  ok() {
    this.failures = 0;
    this.quota = false;
    return this.base;
  }

  /** A poll threw.  Returns the delay to wait before the next attempt,
   *  in ms, along with what the failure was classified as. */
  fail(err) {
    const { kind, status } = classify(err);
    this.failures += 1;
    if (kind === "quota") this.quota = true;
    // 2^(failures-1) so the first failure waits `base`, not 2×base.
    const grown = Math.min(
      this.cap,
      this.base * 2 ** Math.max(0, this.failures - 1),
    );
    // Out of daily budget: waiting longer cannot help within the day, so
    // sit out a full quota window rather than re-asking every minute.
    const floor = this.quota ? Math.max(grown, this.quotaFloor) : grown;
    // Equal jitter: half the delay is fixed (so backoff really is
    // slower), half is random (so N bridges don't resynchronise into
    // one thundering herd when the quota resets).
    const delay = floor * (1 - this.jitter + this.jitter * this.rand());
    return { delay: Math.round(delay), kind, status, failures: this.failures };
  }
}

/** The long-poll hold, capped so it can never exceed the poll period —
 *  otherwise the relay is held open continuously and the "period" is a
 *  lie. */
export function holdFor(interval, wait) {
  const i = Math.max(1, Number(interval) || 60);
  const w = Number(wait);
  if (!Number.isFinite(w) || w <= 0) return 0;
  return Math.min(w, Math.max(1, Math.floor(i / 3)));
}
