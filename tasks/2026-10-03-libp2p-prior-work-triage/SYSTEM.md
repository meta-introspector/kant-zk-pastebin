# Task: libp2p-prior-work-triage

- **Name:** libp2p-prior-work-triage
- **Priority:** P2 → **P0** (revised 2026-10-03)
- **Area:** kant-zk, p2p, libp2p, ipfs
- **Status:** **superseded in part — the work is further along than this task
  assumed. See the correction below.**
- **Created:** 2026-10-03
- **Revised:** 2026-10-03, after reviewing PR #9
- **Tags:** kant-zk, p2p, libp2p, ipfs

## Correction: the work is not stranded

This task was written from the `wip/*` branch state and said the libp2p work
was *"369 lines, never merged, never executed, imported by nothing"*, carried
forward only by an accident of a dirty-worktree snapshot.

**That was wrong.** Reviewing PR #9 (`feature/big-merge` → `main`) on
2026-10-03:

| | this task claimed | actual |
|---|---|---|
| `web/kant-libp2p.mjs` | 369 lines | **690 lines** |
| tests | none | **`web/libp2p-test.mjs`, 768 lines, 45 checks** |
| Rust side | absent | **`src/libp2p_frames.rs`, `src/libp2p_transport.rs`** |
| execution | never run | 45 libp2p checks + 75 `cargo test --lib` |
| "libp2p for file chunks" | not started | **done** — `52349366`, `b23c518f`, `f360e985` |

PR #9's own plan file states it plainly: *"It does not cover libp2p transport
for file chunks — that is done (`52349366`, `b23c518f`, `f360e985`)."*

What I was looking at was a **stale snapshot on a `wip/*` branch**, not the
current state of the work. The real version lives on `feature/big-merge`.

Two things make this worse than a simple "my earlier note was stale":

1. **The 369-line branch is still there**, so the stale artifact remains
   discoverable and will mislead the next reader exactly as it misled me.
   `web/kant-libp2p.mjs` now exists in two places at two different sizes with
   no marker saying which is current.
2. **PB-32 as written would have caused real damage** — "decide adopt / repair /
   discard" applied to a 690-line tested implementation would likely have
   concluded "discard", throwing away working code plus 45 passing tests.

## Revised scope: triage what is actually left

The question is no longer *whether* to adopt the libp2p work. It is:

1. **Land it.** 690 lines + 768 lines of tests + two Rust modules, unreviewed
   and unmerged, on a PR that cannot currently go green (CI fails on a missing
   Docker Hub secret, not on this code).
2. **Remove the stale `wip/*` copies** so there is one `kant-libp2p.mjs`.
3. **`helia-integration`** is listed as out of scope in PR #9's own plan. Still
   not started. No `kant-helia.mjs` or `helia-vendor/` on
   `feature/big-merge` — the earlier claim that they exist was also from the
   stale branch.
4. **Phase 2 risk drops substantially.** A working, tested libp2p transport
   means the §8.4 direct path is not a Phase 2 build — it is mostly Phase 2
   *integration*. That is the single largest de-risking finding of this review.

## The lesson, recorded because it is the same one as before

I read a branch, saw 369 unreviewed lines, and wrote "triage this". The actual
work was 690 lines with 45 tests, done the same day. **Before triaging
something as unmerged-or-stranded, check the actual head of the branch the work
claims to be on, and grep the PR list.** `wip/*` snapshot branches are not a
reliable index of current work — they are a snapshot of one moment, and this
repo has 16 worktrees and many such branches.

This is now the fourth instance this session of a confident claim made from a
stale or wrong source. The pattern worth naming: **absence of evidence on one
branch was read as absence of the work.**

## Non-goals

Not re-litigating the transport design, and not reviewing the 45 tests
line by line — that is a normal PR review, not a triage. What this task now
tracks is: land it, delete the stale copy, decide helia.

## Related

- `2026-10-03-federated-relay-spec` (PB-28) — parent
- `2026-10-03-non-do-relay-research` (PB-33) — the no-DO path
- PR #9, which also carries `tasks/federated-p2p-relay/{SYSTEM,PLAN}.md` —
  a **prior, independent** plan for the same spec. Cross-checked in
  `2026-10-03-pr9-relay-plan-crosscheck`.