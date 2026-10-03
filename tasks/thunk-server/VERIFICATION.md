---
name: thunk-server-verification
priority: HIGH
depends_on: thunk-server
---

# Verification: the claim ledger

**Date:** 2026-10-03 · **Status:** green (26/26) · **Companion to**
[SYSTEM.md](SYSTEM.md), [WASM.md](WASM.md), [IPFS-IPDL.md](IPFS-IPDL.md),
[TOOLCHAIN-THUNKS.md](TOOLCHAIN-THUNKS.md), [THUNK-CYCLE.md](THUNK-CYCLE.md),
[SANDBOX.md](SANDBOX.md)

## Why this file exists

Three separate mistakes in one session had the same cause: acting on a picture
of the tree that had stopped being true.

1. A PR was reviewed against `feature/big-merge` when it targeted `main`, and
   produced two confident wrong findings.
2. `git merge-base --is-ancestor` was run against the *local* `main`, which had
   diverged. That reported "already merged", which retracted two **correct**
   findings and closed the PR on a false premise. `gh pr view` says
   `mergedAt: null`.
3. A fix was written from a `main` 213 commits stale — for a sink `origin/main`
   had already removed. The 1-file commit showed 645 changed files on GitHub and
   that number was read as decoration.

The fix that worked was `scripts/base-check.sh`. This file is the same idea
applied to prose: **the five documents are only as good as the numbers in them,
and a number that was true when it was written is not evidence later.**

## How to run it

```bash
node scripts/thunk-claims.mjs           # table, exit 1 if any claim fails
node scripts/thunk-claims.mjs --json    # rows as JSON
node scripts/thunk-claims.mjs --list    # ids and claim text
node scripts/thunk-claims-test.mjs      # the checker, tested against itself
```

No network. `scripts/relay-telemetry.mjs` used to poll the fleet on import; it
now only runs its collector when invoked directly, because a ledger that made
three HTTP requests per run is a ledger nobody runs offline.

## The two kinds of claim

This distinction is the whole reason the ledger is trustworthy rather than
decorative.

| kind | red means |
|---|---|
| **health** | something regressed. Investigate. |
| **defect** | a known defect got **fixed**. The claim is now wrong and needs rewriting. |

Five claims are defects on purpose. They assert that something is still broken,
which is the only way a fix can announce itself:

| defect claim | asserts | goes red when |
|---|---|---|
| `schedule-has-no-constraint` | the scheduler has no budget vocabulary | phase 6 lands |
| `ref-never-resolved` | nothing calls a resolver on a ref target | the IPDL resolver lands |
| `nora-wildcard-version` | `rust-unixfs` is still `version = "*"` | the version is pinned |
| `wasm-test-reads-gitignored-dist` | the test still reads gitignored `dist/` | the test reads the embedded copy |

Three defect claims have now done their job. `thunk-load-throws` and
`apply-double-wraps` went red the moment phase 0 landed, and `thunk-id-truncated`
went red when phase 1 landed — all three were rewritten as health claims, and
replacements took their place: `sandbox-has-no-require`, `sandbox-refuses-console`
and `sandbox-refuses-dynamic-import` for phase 0; thirteen more for phase 1,
covering the content hash, the call id and the float type.

`thunk-id-truncated` is the one worth dwelling on. Its probe was
`/\.slice\(0,\s*16\)/.test(src)` — a claim about a *spelling*. When phase 1
replaced that line with a `valHash` call, the claim had nothing left to read,
and the mutation that tested it had nothing left to break. The thirteen
replacement claims are written the other way round: they run the real code and
assert behaviour, so rewriting the implementation correctly does not invalidate
them. `thunk-id-separates-urls` loads two thunks that differ only in a URL and
requires different ids — no implementation detail appears in it at all.

That is the whole lesson of the three mistakes, applied to the checker: a claim
written as "this line contains X" stops holding when the code is fixed, and the
failure looks identical to a regression.

The CLI says which kind of red you are looking at, so a fix does not get mistaken
for a regression:

```
3 health claim(s) went red — that is a regression.
1 defect claim(s) went red — that is progress; rewrite them.
```

## Claims pin text; tests pin behaviour

The ledger's probes are mostly pattern matches over source text, and a text claim
can only ever say "this string is still there". That is a real limit and it is
why the behaviour has its own file: `server/sandbox-test.mjs` enumerates 13
escapes and runs them, and it was verified to have teeth by reintroducing the
host-object realm bridge and watching two of its cases fail.

The division of labour: **a claim says the code says this, a test says the code
does this.** Neither substitutes for the other, and the gap between them is
where phase 0's three surviving escapes lived — the two sandbox tests in
`server/thunk-test.mjs` went green on the first fix while `module.constructor`,
`this.constructor` and `console` were all still open.

## The checker is tested against itself

`scripts/thunk-claims-test.mjs` — 17 checks. Two of them are structural: ids are
unique, and the ledger refuses to shrink below 20 claims so it cannot be
truncated into agreement. The other fifteen are **mutations**: each feeds a
claim's real probe an input that should break it and asserts the claim goes red.
A probe that cannot be made to fail is not a probe.

One of those mutations earned its place the hard way. The counter-example for
`kernel-imports-zero` was originally hand-assembled wasm with a miscounted
section size. It "passed" — because the probe *threw* on invalid bytes, which is
indistinguishable from the probe having seen an import. The test now asserts the
counter-example really has exactly one import before trusting it. That is the
same class of error as the collector that reported "100 POSTs" when the limiter
had accepted 10, and the reason the assertion is there rather than a comment.

## What the ledger covers

| group | claims |
|---|---|
| the payload | 799 bytes · zero imports · 21 exports · under 5% of a frame · embedded copy byte-identical · `KERNEL_LENGTH` agrees · `kernelBytes` is a function |
| identity | id truncated to 16 · `asWitness` needs 64 |
| thunk mechanics | loader throws · `apply()` double-wraps · `snapshot()` deep-copies |
| scheduler | has `add`/`remove`/`tick`/`installManifest` · has no constraint |
| IPDL | 3 `IPDL_REF` sites · no resolver · a ref round-trips with a stable 64-hex hash |
| build inputs | every flake input is a 40-hex github pin · one wildcard crate version |
| cadence | 11s sustainable · 0.5 headroom |
| secrets | the sops entry point, config and registry all exist |
| latent failure | the wasm test reads a gitignored directory |

The IPDL round-trip claim uses the **real nixpkgs pin from `flake.nix`**, not a
fixture, so it is a claim about this tree's actual reference rather than about a
made-up string.

## What the ledger deliberately does not cover

- **Claims about other repositories.** §4 of [THUNK-CYCLE.md](THUNK-CYCLE.md)
  costs a lens at 16 subprocess spawns per discovery pass and one full pass over
  the hit file per service, measured against `dasl-tiles-rust/src/stream.rs`.
  That file is not in this tree, so nothing here can keep those numbers honest.
  They are cited, dated, and unverified by machine.
- **Anything about the deployed fleet.** `/stats` returns 404 on all three known
  workers, so the storage split is committed but not deployed and there are no
  per-room counters to pin.
- **Judgements.** "the api set belongs in the call id, not the thunk id" and
  "where a lens's ambient input goes" are argued, not measured. They stay in the
  Open sections of their documents, which is where an unproven claim belongs.
- **Whether the sandbox is *enough*.** [SANDBOX.md](SANDBOX.md) records a
  default-deny policy and 13 enumerated escapes, all closed. `vm` is a fresh
  realm with no host authority, not a hardened security boundary, and the
  ledger cannot argue that difference either way.
- **The api set that policy points at.** A `js` thunk that needs the filesystem
  is refused today, correctly, because `THUNK-CYCLE.md` phase 3 has not landed.
  A capability that is refused is recoverable; one that was ambient is not.

## Adding a claim

One entry in `CLAIMS`: an `id`, the claim in a sentence, the `doc` it backs, its
`kind`, one input (`T` text, `B` binary, `D` derived, `RUN` for "just do it"),
the expected value, and a **pure** probe with no file access. Then add the
mutation to `thunk-claims-test.mjs`. A claim without a mutation is a comment.

If the claim is about behaviour rather than about a string, add it as a test
instead. `thunk-loads` is the borderline case — it runs a real thunk and checks
the state, which is behaviour — and it is worth having in both places, because
the behavioural version is the one that would notice a break the text version
cannot see.

`SELF` at the top of the file lists the two files excluded from the
`ref-never-resolved` scan, because a claim that greps for a name inside its own
regex literal always fails. That exclusion is the one place this file is allowed
to be about itself.