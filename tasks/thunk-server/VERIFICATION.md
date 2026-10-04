---
name: thunk-server-verification
priority: HIGH
depends_on: thunk-server
---

# Verification: the claim ledger

**Date:** 2026-10-04 · **Status:** green (53/53 claims, 59/59 checks, 44/44 suites)
· **Companion to**
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

## The recorded cause was wrong every single time

**Flagged because it is the rule that would have saved all of this.** Every
defect recorded in this ledger named a cause, and not one of those causes was
accurate enough to act on. In each case, fixing exactly what was written would
have left the suite red:

| recorded cause | what was true | re-derived by |
|---|---|---|
| `web/wasm-test.mjs` "reads `dist/kant_kernel.wasm`" | it read **two** gitignored files; the second, `kernel-vectors.json`, was never named | `wasm-test-inputs-tracked` |
| five suites "look for `scripts/index.html`" | wrong for `scripts/site-test.mjs`, which was failing on `scripts/kant.config` | `scripts-suites-delegate-to-their-web-twin` |
| "`scripts/kant-debug.mjs` does not exist" | true of this branch, **false of the repository** — it is on `origin/feature/lean` and `origin/feat/build-feed`; the big merge dropped it | `kant-debug-is-tracked` |
| carddebug "**imports** `scripts/kant-debug.mjs`" | it *spawns* it as a child process, which is why it went unnoticed next to four suites that really do import it | `kant-debug-is-spawned-not-imported` |
| `scripts/net-test.mjs` "not hermetic, binds a real port" | the port was irrelevant. It left `passDb` at `/var/lib/kant-zk/passes.sqlite` and was writing to the live relay's rate-limit ledger | `suites-write-only-into-their-own-temp-dir` |
| `web/libp2p-test.mjs` excluded as "starts a relay" | its own first paragraph says the pubsub node is injected "so this runs with no network, no daemon and no CDN". It starts nothing. Same for `scripts/room-store-test.mjs` ("starts a relay" — "every relay here is a fake") and `scripts/relay-measure-test.mjs` ("needs a live relay to measure" — it imports three pure functions and runs in 0.65s) | `excluded-reasons-match-the-tree` |

The third column is not decoration. `recorded-causes-are-re-derived` reads this
table out of the file, requires every row to name a claim, requires those
claims to exist, and **runs them against the tree** — so the sentence above
cannot outlive the code it describes, and a claim cannot be deleted without this
table going red. That is the whole promise of the section: a recorded cause is a
hypothesis, and the first thing to do with one is re-derive it.

The sixth row was found by applying the rule to the runner's own manifest. The
`EXCLUDED` map is a list of recorded causes — one per suite — and **three of the
seven were wrong in the same way the first five were**: written from the file's
name or its neighbourhood instead of from the file. Two said "starts a relay"
about suites that start none, and one — `scripts/relay-measure-test.mjs` — was
excluded for "needs a live relay to measure" while running in 0.65s with no relay
anywhere in it. It is in the core run now. What fixed the two that were right to
be excluded was not cleverness: one of them says "every relay here is a fake" in
its own header, and the other says the pubsub node is injected. Both sentences
were already in the files.

The pattern is not bad luck. A cause is recorded as the first plausible
explanation, and a plausible explanation is exactly what survives being written
down. Two of the first five were *incomplete* (a real cause, missing a file), two
were *wrong in a way that pointed the fix backwards* (delete the test instead of
restoring the tool; audit the port instead of the database), and one was right
about the symptom and wrong about everything behind it. The sixth is the purest
case of all: nobody had opened the file.

So: **a recorded cause is a hypothesis, and the first thing to do with one is
re-derive it from the tree** — not from the sentence someone wrote about it.
Where a cause is cheap to re-derive, make the re-derivation the claim itself,
which is what `scripts/thunk-claims.mjs` is for. Where it is not, say plainly
that the recorded cause is unverified.

### And then: the other four documents are full of numbers nobody re-derived

The rule above was applied to this file's own table. It had not been applied to
the four documents sitting next to it, which state counts in prose — `SYSTEM.md`
and `SANDBOX.md` say `server/thunk-test.mjs` is **20/20 green**, both say
`server/sandbox-test.mjs` enumerates **13** escapes, `WASM.md` says **16** tests,
**91** checks, **59** vectors, a **13**-module closure, **21** exports, **799**
bytes, **5%** of a 16 KiB frame, and `server/pass-store.mjs:75`.

**Two were already wrong.** `server/thunk-test.mjs` prints 21, in both files. A
count in prose is the same recorded cause as a cause in prose and it rots the
same way; it took the rule being written down to find the first two.

`stated-counts-match-the-tree` parses twelve of those numbers out of the four
documents and re-derives each one. Ten of the twelve are re-derived by *running
something* — a suite's check count is what it prints, not what a grep for
`check(` says — and the other two by parsing an artefact (`kernel-vectors.json`,
`git ls-files lean-gate`) or reading a declaration (`KERNEL_EXPORTS`).

Three details are the claim rather than the arithmetic:

* **An enumerated case list is counted from the array, not from the tests.**
  `server/sandbox-test.mjs` has 13 escapes and **17** tests: the loop adds a pure
  thunk and two transducer cases. A derivation that counted `t(` calls, or read
  the suite's own summary line, would have agreed with the stale 13 forever.
* **A proportion is checked as a proportion.** "799 bytes is 5% of one 16 KiB
  frame" is checked as `round(bytes / FRAME_BYTES * 100)`, so a kernel that grows
  does not make the sentence wrong while the sentence is still true.
* **A count that cannot be read is not a count that agrees.** Every number here
  is found by a regex over prose, and prose is edited. A regex that stops
  matching yields `stated: null`, and the probe refuses that rather than reading
  it as agreement — the same vacuity trap as an emptied ledger.

`MIN_STATED_COUNTS = 12` covers the other direction: a row deleted from the input
leaves a shorter array that agrees with itself. Like `MIN_RECORDED_CAUSES` it is
a stated number, so lowering it is a visible edit rather than a quiet one.

Five mutations make it go red — a stale count put back, a fourteenth escape added
to the array without a doc edit, a comment inserted above `admit()` so the line
number moves, a byte count changed, and a row whose number cannot be found at
all. The escape one is the one a grep cannot do.

### And then the guard's own trigger rotted

The fifth row has a sequel. `suites-never-use-the-production-pass-db` found the
production ledger by asking whether a suite **spawns** `relay.mjs`. That was
true when it was written, and it stopped being true on the very commit that made
the suites start passing: the four suites with an inline `spawn` were collapsed
into `scripts/relay-start.mjs`, so the word `spawn(` left their source and they
dropped out of the guard — one of them while pointing `--log` at
`web/.diag-relay.log`, inside the checkout.

A guard whose trigger is a spelling rots the moment the spelling is fixed, and
it rots *silently*, in the direction that looks like success. So the trigger is
now derived too: `relayPathKeys()` takes every path key out of `server/relay.mjs`'s
own `CONFIG` (there are three that are written, not one), and
`spawnsRelayProcess()` reads the spawn's **argument list** rather than the file.
Generalising it immediately found three more writes, all of them real:

* `web/file-test.mjs` handed the relay a *fixed* `/tmp/kant-file-test/passes.sqlite`
  and `/tmp/kant-file-test/archive` — not production state, but shared by every
  concurrent run of that suite, which is the same defect one level down.
* `web/diag-test.mjs` wrote its relay log to `web/.diag-relay.log`, in the tree.
* `web/diag-test.mjs` called `resolveReachability({ configured:
  "https://kant-relay.cicada71.net" })`, which **really did fetch
  `https://kant-relay.cicada71.net/health`** — from the core run, on every
  `npm run verify`, against the deployment this repository is for. The suite was
  called hermetic and it was phoning home.

The last one is `suites-never-reach-a-remote-host`, and it has the same two
halves: no suite may point a request at a host outside loopback, and a suite
that names one anyway must have handed the call a `fetch` of its own. The
`https://` matters here: a comment stripper that is really a regex deletes
`https://…` along with the comment, and a check that cannot see a URL is a check
that passes.

Two corollaries that cost real time here:

* **Watch the artefact, not the exit code.** Every one of these was found by
  looking at something outside the test — a database's row count, a temp
  directory, `git cat-file` on another branch. A suite that exits 0 tells you
  only that it did not crash.
* **A guard is not a guard until it has been made to fail.** Two drafts of
  `suites-never-use-the-production-pass-db` passed green under mutation; both
  defects were found only by breaking a suite and watching the claim stay
  happy. An audit that has never been seen to fail is not known to work.

## How to run it

```bash
node scripts/thunk-claims.mjs           # table, exit 1 if any claim fails
node scripts/thunk-claims.mjs --json    # rows as JSON
node scripts/thunk-claims.mjs --list    # ids and claim text
node scripts/thunk-claims-test.mjs      # the checker, tested against itself

npm run verify                          # the core run, once each
node scripts/check-all.mjs --repeat 5   # the same run, five times each
node scripts/check-all.mjs --repeat 5 --only web/net-test.mjs
```

No network. `scripts/relay-telemetry.mjs` used to poll the fleet on import; it
now only runs its collector when invoked directly, because a ledger that made
three HTTP requests per run is a ledger nobody runs offline. The same rule now
has teeth: `suites-never-reach-a-remote-host` fails if any tracked suite hands a
request to a host that is not loopback.

### `--repeat`, and why one green run is not a result

`scripts/net-test.mjs` passed three times and failed the fourth with
`relay post 2 line(s) failed: 429`, and the cause recorded at the time — "it
binds a real port" — was wrong: an ephemeral port is hermetic, and what it was
doing wrong was appending to `/var/lib/kant-zk/passes.sqlite`, whose counters are
windowed and so accumulate across runs.

A runner that reports one green run as `ok` cannot tell a suite that is right
from a suite that is *usually* right. So `--repeat N` runs each suite N times and
sorts the outcome three ways, because the difference between the last two is the
whole point:

| verdict | meaning |
|---|---|
| `stable pass` | passed every run |
| `UNSTABLE` | passed some — **this is the one a single run cannot see** |
| `stable fail` | failed every run, which is what an ordinary run already reports |

With `--repeat 1` the runner says so in as many words rather than implying a
stability result it cannot support. The classifier is `classifyRepeats()` in
`check-all.mjs`, exported and unit-tested in `thunk-claims-test.mjs`; that test
fabricates its outcomes deliberately, because the function's entire job is the
mapping from what was observed to a verdict and there is no tree for a fake row
to misrepresent.

Run on 2026-10-04, with a load average of 19 on 24 cores:

```
node scripts/check-all.mjs --repeat 3 --only scripts/net-test.mjs,web/join-test.mjs,\
scripts/codec-test.mjs,scripts/carddebug-test.mjs

  ok     3/3     57ms  scripts/codec-test.mjs       codec: 91 checks passed
  ok     3/3  31337ms  web/join-test.mjs            29/29 checks passed
  ok     3/3    191ms  scripts/carddebug-test.mjs   73/73 checks passed
  ok     3/3  48094ms  scripts/net-test.mjs         all 51 discovery / relay checks passed

no suite changed its mind over 3 runs (4 suites checked)
```

**Zero found, including `scripts/net-test.mjs`** — the suite whose fourth run
used to 429. That is the expected answer now that it delegates and keeps its
pass database under its own `tmpdir()` name, and the ledger claims
`suites-write-only-ininto-their-own-temp-dir` is what makes it so. A negative
result from a repeated run is still a result, and it is worth recording: three
runs at load 19 says nothing about a hundred.

## What actually runs it

`npm run verify` (or `node scripts/check-all.mjs`). Until 2026-10-03 the
repository had **fifty tracked `*-test.mjs` files and nothing that ran them**:
`npm test` is a puppeteer test that needs a live server, and the Makefile has no
test target. That is the mechanical reason a `float` constructor could be added
to a shared codec with every suite green — nobody was running them.

The runner executes 44 hermetic suites, including both Lean cross-checks and
this ledger. Four properties it is built to keep:

- **It does not hide failures.** Every tracked suite must be in `CORE` or
  `EXCLUDED`, and the ones left out carry a stated reason which is itself a
  claim (`excluded-reasons-match-the-tree`). A runner that silently omits broken
  files reads as coverage.
- **It cannot fall behind the tree.** One tracked suite in neither list fails the
  run. This caught `web/sharelog-test.mjs` on its first execution, which had been
  missed by hand.
- **It runs what it claims to, every time.** No caching, no remembered results.
- **It says when a suite is only sometimes right.** `--repeat N`, below. A single
  green run cannot tell a correct suite from a usually-correct one, and
  `scripts/net-test.mjs` passed three times before failing the fourth.

It has teeth: changing one byte in the codec's `str` tag — `S` to `s` — turns
**five independent suites** red and exits 1:

```
FAIL  scripts/codec-test.mjs           39 of 91 checks FAILED
FAIL  server/thunk-test.mjs            20 passed, 1 failed
FAIL  scripts/thunk-claims.mjs         exit 1
FAIL  scripts/thunk-claims-test.mjs    21 passed, 4 failed
FAIL  scripts/lean-codec-vectors.mjs   4/8 checks pass
```

### The ten broken suites

Worth having in one place, since nothing had them. **All ten are fixed.** The
core run is 44 suites and `check-all.mjs` reports `no tracked suites are broken`.

| suites | why it was broken | fix |
|---|---|---|
| `scripts/wasm-test.mjs`, `web/wasm-test.mjs` | read gitignored `dist/` — *two* files, not the one the claim named | `scripts/embed-kernel.mjs` writes the artifacts to `web/` as tracked files; `scripts/` copy delegates |
| `scripts/{cli-page,diagpage,handpage,page,site}-test.mjs` | resolved their HTML and config against `scripts/`; the pages live in `web/` | delegate to the `web/` copy, which is a superset of each |
| `scripts/carddebug-test.mjs`, `web/carddebug-test.mjs` | shell out to `scripts/kant-debug.mjs`, which the big merge dropped | restored byte-for-byte from `origin/feature/lean` |
| `web/cli-page-test.mjs` | `box.querySelectorAll is not a function`, then a transcript assertion reading markup the renderer stopped emitting | shim gained `querySelectorAll`; assertion reads the current markup |

Three of these were not what the ledger said, and that is the part worth
keeping. Each one was recorded with a *spelling* of its cause, and the spelling
was wrong or incomplete in all three:

- **`wasm-test-reads-gitignored-dist`** named `kant_kernel.wasm` only. The test
  also read `dist/kernel-vectors.json`, so fixing the named file would have left
  it still dying with ENOENT.
- **"looks for `scripts/index.html`"** was wrong for `scripts/site-test.mjs`,
  which was failing on `scripts/kant.config`.
- **"imports `scripts/kant-debug.mjs`, which does not exist"** was true of this
  branch and false of the repository. `git log --diff-filter=D` — the check the
  task file itself asked for — showed the file was never deleted: it is on
  `origin/feature/lean` and `origin/feat/build-feed`, byte-identical, and never
  reached `feature/big-merge`. So the tool was restored rather than the test
  deleted, which was the other option and the wrong one.

**Two assertions could not fail, and both were passing.**

`web/page-test.mjs`'s twin `$("btn-dojoin").click()` was not awaited. The join
handler is async, so the assertions after it were asserting before it had
settled — the comment in the `web/` copy says so: "passing for the wrong
reason". The two copies had drifted, and the stale one was the wrong one.

`web/cli-page-test.mjs` compared the page's transcript against the terminal's
positionally, with a regex for markup `lineHtml` stopped emitting, so it matched
nothing and reported `[]`. That same check also asked the page to reproduce the
terminal's *order*, which the page explicitly does not promise: `web/index.html`
states that an untimed line "still shows, sorted last and marked, rather than
vanishing", and `kant-cli.mjs say` sends no clock. Comparing multisets keeps the
intent — every message the terminal shows, and nothing it does not — without
demanding a promise the code declines to make. Mutation-tested: renaming the
`body` span in `kant-pretty.mjs` turns it red.

**A product bug the assertions were hiding.** `daySections` in
`web/kant-pretty.mjs` read `d.untitled`, but `byDay` in `web/kant-net.mjs` sets
`untimed` — two names differing by two letters, and `UNTITLED` is also the day
*value*. So the untitled bucket fell through to `dayLabel("untitled")`, i.e.
`new Date("untitled")`, and the page headed that section **"Invalid Date"**.
`web/pretty-test.mjs` passed throughout, because its fixture was
`{ day: "UNTITLED", untitled: true }` — matching neither the value nor the flag
any real caller produces. The fixture is now built by `byDay` itself, and
reverting the one-word fix turns the test red.

One more, found while building this: **`scripts/net-test.mjs` is not hermetic**
despite looking like its `web/` twin. It binds a real port and posts to a live
relay, so it 429s under repetition — it passed the first survey by luck and
failed every run after. That is why the core set is a hand-written manifest with
a stated reason per entry rather than something inferred by grepping for
`fetch(`: a grep would have called it hermetic too.

### Six suites were writing production state

That last entry turned out to be the visible symptom of something larger, and
the diagnosis inverted twice on the way.

**The bind was never the problem.** `scripts/net-test.mjs` flaked with
`relay post 2 line(s) failed: 429`, which reads like a port conflict. It is the
rate limiter: `passes.admit` allows `peerLimit` (10) posts per `peerWindowMs`
(10 minutes) per (room, sender), counted in SQLite. The suite configured its
relay with `{ ...CONFIG, port: 0, host: "127.0.0.1", staticDir: "" }`, leaving
`passDb` at its default of `/var/lib/kant-zk/passes.sqlite`. That is
deployment state. Its counters are windowed, so they accumulated across runs:
three passes, then a 429 of its own making. Its `web/` twin already had the fix
— a per-PID SQLite in `tmpdir()`, and a comment explaining exactly this — so the
stale copy was simply the one written before it.

**`createServer` is not the only way in.** Auditing every suite by watching
`/var/lib/kant-zk/passes.sqlite` during `npm run verify` found four more
writers, and three of them were invisible to the obvious grep:

| suite | how it reached production | rows per run |
|---|---|---|
| `scripts/net-test.mjs` | in-process `createServer`, `passDb` left at the default | 3–10 |
| `web/join-test.mjs` | in-process, and **in the core run** | 5 |
| `web/diag-test.mjs` | *spawns* `server/relay.mjs` with no `--pass-db` | prunes + writes |
| `web/cli-page-test.mjs` | spawns it — **my own file, from the previous commit** | 3 |
| `scripts/diag-test.mjs`, `web/cli-test.mjs` | spawn it (both in `EXCLUDED`, so a core-only audit misses them) | 3, 6 |

`createServer` opens the pass store eagerly, so even a suite that never POSTs
opens the live ledger. All nine relay-touching suites now pass their own
database, and `npm run verify` adds **zero rows** to production where it
previously added a dozen.

**A suite that could not fail.** `scripts/vacuum-bug-test.mjs` had no
`process.exit` anywhere: `main().catch(console.error)` swallowed even a crash,
so it exited 0 unconditionally. It also talked to whatever was listening on
`127.0.0.1:8787` — a relay it never started — so with no relay up, every CLI
call errored and it still reported success. It now starts its own relay on a
reserved port with its own pass database, treats every step as a precondition,
and exits non-zero when one fails.

What it still cannot do is see the bug it is named for. The symptom was a tab
that was open but not polling; a CLI `read` resumes from a stored cursor and so
always sees the message. The script says so in its output rather than claiming
the bug is fixed.

`suites-never-use-the-production-pass-db` now guards all of this, and it earns
its keep: it caught `web/wasm-test.mjs` — the file I had written the previous
commit — and then caught two more suites the core-only audit had missed. Its
first two drafts were wrong in instructive ways. Grepping the file for the word
`passDb` passed a suite that declared it and never passed it, so it now resolves
the config that actually reaches `createServer`/`createRelay`. It then matched
`node:http`'s own `createServer` — the 404 stubs — and built a `RegExp` out of
the string `(_req`. Both were found by mutating a suite and watching the claim
stay green, which is the only reason they were found at all.

Known limitation: one run of `npm run verify` exited 1 with no failing suite
printed, and four subsequent runs were clean. The failing suite was not
captured, so the cause is unknown — most likely contention with the concurrent
agent in the same tree, but that is a guess and not a measurement.

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

Four defect claims have now done their job. `thunk-load-throws` and
`apply-double-wraps` went red the moment phase 0 landed, and `thunk-id-truncated`
went red when phase 1 landed — all three were rewritten as health claims, and
replacements took their place: `sandbox-has-no-require`, `sandbox-refuses-console`
and `sandbox-refuses-dynamic-import` for phase 0; thirteen more for phase 1,
covering the content hash, the call id, and the refusal of an argument that has
no content address. `wasm-test-reads-gitignored-dist` went red when the kernel
test was made hermetic, and became two health claims: `wasm-test-inputs-tracked`
(asks git whether every artifact the test opens is tracked, so it fails on the
`dist/` read returning) and `kernel-vectors-satisfy-wasm` (replays all 59 golden
vectors against the tracked binary).

That last pair is the first to be written the way this ledger wants: not
"this line mentions `dist/`" but "git says whether these files are tracked", and
not "the file has 59 entries" but "the binary satisfies all 59". Each was
mutation-tested against the real regression, not a fabricated input.

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

**And a claim written only in JS cannot see a divergence from Lean.** The first
version of `codec-has-a-float` asserted that the codec had a float type, and it
was right about the JS and wrong about the format: `RequestProject/Kant/Codec/
Val.lean` has six constructors, no float, and a proof of `canonEnc_injective`
over them, and IPDL drops floats for binary compatibility while proving the
projection `LOSSLESS`. Every JS test passed. The claim is now `codec-has-no-float`,
and it reads the codec rather than the Lean source — because the Lean source is
three git worktrees away and not part of this repository, so there was nothing
here to disagree with it.

That is the same shape as the three mistakes, one level up: I had a picture of
the codec that was true of the JS and had stopped being true of the thing the JS
is a transcription of.

### The guard that closes it

`LEAN_VAL_TAGS` is the list of shapes `RequestProject.Kant.Codec` can name — the
six `Val` constructors plus `ref` and `annot` from `Ipdl`. `isLeanRepresentable()`
walks a canonical value and answers whether Lean could have built it, and
`thunkDefinitionVal()` exposes what a thunk id is actually hashed over so
something can check.

A thunk id that Lean cannot reproduce is an id the swarm cannot verify against a
proof, so this gates the id rather than the codec.

### The check that keeps the list honest

`LEAN_VAL_TAGS` is a hand-transcribed list, which is the same failure mode one
level down — a claim about the tree that can stop being true. So
`scripts/lean-codec-types.mjs` re-derives it from the Lean source and compares.

`LEAN_VAL_TAGS` in `server/thunk-id.mjs` is the list of shapes
`RequestProject.Kant.Codec` can name — the six `Val` constructors plus `ref` and
`annot` from `Ipdl`. `isLeanRepresentable()` walks a canonical value and answers
whether Lean could have built it, and `thunkDefinitionVal()` exposes what a thunk
id is actually hashed over so something can check it.

This is the check a JS-only suite cannot make, and the reason is structural
rather than an oversight: **a seventh tag does not collide with the other
seven.** Every round-trip test, every injectivity test and every projection test
keeps passing while the two implementations have quietly stopped agreeing. The
float would have shipped on a fully green test run.

Two things this guard is honest about:

- It knows the tag list, not the Lean proofs. It cannot tell you `Val` changed;
  it can only tell you that JS is using a shape the recorded list does not
  contain.

**Both of those limits are now gone**, because the Lean source turned out to be
in *this repository* — on `feature/lean`, not on this branch and not a flake
input. An earlier reading of the tree concluded it was external and
unverifiable; that was wrong, and `find` was the reason.

`scripts/lean-codec-types.mjs` reads `RequestProject/Kant/Codec/Val.lean` and
`Ipdl.lean` with `git show` at a pinned commit (`a3cd85b4`, on `origin`) and
parses the constructors out of the declarations, so a constructor added to Lean
shows up without this file being edited. It then compares three things: the tags
`canonEnc` encodes, Lean's constructors, and `LEAN_VAL_TAGS`. All three agree —
six canonical types plus `ref` and `annot`.

It reads the `switch (v.t)` in `canonEnc` rather than calling the constructors,
because calling them does not work: `vInt(null)` throws from `BigInt` and
`vStr(null)` returns the tag `str` for a value that was never a string, so a
probe both misses types and invents them. That was the first version, and it
reported three types.

**It has teeth.** Re-adding `case "float":` to `canonEnc` — the exact phase 1
mistake — turns two of the four checks red and names `float` in both.
`thunk-claims-test.mjs` does this on every run and restores the file.

**It does not false-pass.** With an unreachable pin it exits 2 and prints
`git fetch origin feature/lean` rather than reporting success. That is the whole
design constraint: a checker that skips quietly when it cannot see the thing it
checks reads as a green run, which is the failure it exists to catch.

What remains unverified, and cannot be verified from here: constructor
*semantics* drifting, a `#guard` vector changing, or a Lean proof being weakened.
It compares declarations, not proofs.

### The values, not just the types

`scripts/lean-codec-vectors.mjs` closes the other half. A codec can agree with
Lean about which types exist and still serialise them differently, so this reads
the six `#guard` assertions about `gSample` out of `Tests.lean` and compares
them against what the JS codec actually produces:

```
ok  JS canonEnc matches Lean's #guard      39 chars
ok  JS yamlEnc  matches Lean's #guard     52 chars
ok  JS xmlEnc   matches Lean's #guard    164 chars
ok  JS ipdlText matches Lean's #guard     48 chars
ok  JS valHash  matches Lean's #guard     64 chars
ok  JS csvEncode matches Lean's #guard   281 chars
```

**It does not parse `gSample`'s Lean term.** Since Lean proves
`canonEnc_injective`, two values with the same canonical text are the same value,
so matching all six outputs is enough. Reading the term would be more work and
would prove less.

Two things that bit while writing it, both recorded here because they would bite
again:

- **Lean string literals are not JavaScript's.** `\"` and `\\` are shared, but
  the CSV vector uses the *gap* — a backslash at end of line, which continues the
  string and eats the next line's indentation, six times. Unhandled, the expected
  value silently truncates to its first row and the failure looks like a codec
  bug rather than a parser bug. A raw newline with no backslash is rejected, since
  Lean has no other line-continuation.
- **A `#guard` may wrap onto the next line**, so extraction runs over the whole
  file with the string bodies scanned out first. A line-anchored parse makes a
  wrapped guard invisible, and the vector then goes *unchecked* rather than red.

The mutation flips one byte — `S` to `s` in the `str` tag — and `canonEnc`,
`ipdlText` and `valHash` must all go red. It runs the checker as a **child
process**, because `compareVectors` imports the codec and Node caches ES
modules: re-checking in the same process compares the old module and reports
nothing. The first version of this mutation had no teeth for exactly that
reason, and looked like a passing check. A subprocess is also how CI runs it.

Still not verified: constructor semantics drifting, or a `#guard` that was
weakened rather than satisfied. Both are properties of the Lean side that a JS
comparison cannot see.

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

`scripts/thunk-claims-test.mjs` — 53 checks. Three of them are structural: ids are
unique, every claim names the doc it backs, and the ledger refuses to shrink
below 20 claims so it cannot be truncated into agreement. Most of the rest are
**mutations**: each feeds a claim's real probe an input that should break it and
asserts the claim goes red. A probe that cannot be made to fail is not a probe.

The newest mutations are not of a claim but **of the machinery the claims are
made of**, because a checker that cannot report its own failures honestly is
worse than no checker. Three branches had no test at all: a claim whose input
cannot be read, a probe that throws, and an empty ledger. All three are now
exercised, and the last one is the one that matters — a checker that has been
emptied is a checker that passes.

Two of this session's mutations found guards that were shaped exactly like a
passing row, which is worth writing down because it is the failure mode this
file keeps hitting:

* A `NOT SCANNED` row — a suite that mentions the relay and is then not judged
  — has `outside: 0, paths: 1`, which is the shape of a passing row. The probe
  did not test for it until the mutation that removes a suite from the scan
  proved it unnecessary.
* `fetchImpl: globalThis.fetch` passed the "is this a stub?" check, because
  `\s*` before a negative lookahead backtracks and tests the lookahead against
  the space. The value is now captured and compared.

A third is the reason the section above has a third column: the claim that a
recorded cause is wrong cannot be made to fail by mutating the *claim*, because
the cause is a sentence in a document. So the row names the claim that
re-derives it, and the mutation breaks the tree in the way the row describes.

One of those mutations earned its place the hard way. The counter-example for
`kernel-imports-zero` was originally hand-assembled wasm with a miscounted
section size. It "passed" — because the probe *threw* on invalid bytes, which is
indistinguishable from the probe having seen an import. The test now asserts the
counter-example really has exactly one import before trusting it. That is the
same class of error as the collector that reported "100 POSTs" when the limiter
had accepted 10, and the reason the assertion is there rather than a comment.

## The Lean proof finally has a gate

`web/wasm-test.mjs` checked that the emitted binary computes the 59 golden
vectors. Nothing checked that the *proof* was a proof — the Lean tree is not on
this branch, and where it did live it could not be built.

**The blocker was Mathlib, and the measurement is the argument.** With Mathlib
on `LEAN_PATH`, a two-line file containing only `import Mathlib` did not finish
elaborating in 401 s, and the 26-module closure around `Wasm/KernelSpec.lean`
produced **zero** `.olean` files in 560 s. Eighteen of those 26 modules imported
it. There was no version of "just build the proof" that ran in reasonable time.

`lean-gate/` is that tree with Mathlib removed — thirteen modules, ~3,000
lines, importing nothing outside core Lean 4. `scripts/lean-proof-gate.sh` runs
`gokujo check` with `LEAN_PATH` deliberately unset, and
`scripts/lean-proofs.mjs` wraps it in the core run.

| | cold | warm |
|---|---|---|
| `gokujo check`, 13 modules, no Mathlib | **10.4 / 10.7 / 10.8 s** | **2.65 s** |
| the same closure with Mathlib | **> 560 s, 0 oleans** | — |

Three consecutive cold runs, then a warm one; that is where the numbers above
come from. The gate audits 181 declarations and reports them resting on
`propext`, `Classical.choice` and `Quot.sound` — nothing beyond core Lean 4.

### Removing Mathlib meant two false theorems fell out

Neither could ever have compiled, which is the strongest evidence available
that this part of the tree was never built:

* **`eval_cantorPairE` claimed the kernel computes `Nat.pair`.** Mathlib's is
  `if a ≤ b then 2 * b * (b + 1) + a else …`; `cantorPairE` computes
  `[a < b]·(b² + a) + [a ≥ b]·(a² + a + b)`. At `a = 0`, `b = 1` those are 4 and
  1. The theorem now states what the kernel does, and its docstring records
  that the old claim was wrong.
* **`reassemble_perm` is false as stated.** `fs₁ = [⟨5,5,[1]⟩, ⟨9,9,[3]⟩]`,
  `fs₂ = [⟨5,5,[2]⟩, ⟨9,9,[3]⟩]`: `fs₁.Perm fs₂` and
  `(fs₁.map Frame.seq).Nodup` both hold, but `mergeSort` is stable and nothing
  orders the two 5s, so the reassemblies are `[1,3]` and `[2,3]`. It needed a
  strict hypothesis — distinct frames carry distinct sequence numbers.

Both, and the theorem depending on `reassemble_perm`, are omitted from the gate
tree with the counterexample written out in `Kant/Sneakernet.lean`. They are
not in `KernelSpec`'s closure. `lean-gate/README.md` has the full table of what
each Mathlib tactic was replaced with and why.

### And an 8-second guess, which was the recorded-cause pattern again

The first `npm run verify` after wiring the gate in went red on
`web/cli-page-test.mjs` and its delegating copy: `relay did not start`.

The obvious reading is "the new gate load slowed the box down". That is wrong,
and the way it is wrong is the section above this one. The four-word message
was the defect: four suites each carried their own
`reject(new Error("relay did not start")), 8000`, so a failure carried no
evidence at all — not the relay's stderr, not its exit status. Spawned directly
and timed, the relay takes **10.5 s, 13.6 s, 15.4 s** to say `listening` on
this box with a load average of 15 on 24 cores, because its first SQLite
connection migrates the pass-db schema. The recorded "2.9 s" was an idle-box
measurement; the 8 s budget was never derived from one.

`scripts/relay-start.mjs` now holds one budget, measured, and rejects with
what the relay said. Claim `relay-suites-share-one-start-budget` stops the
copies coming back.

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
| the Lean gate | the proof tree imports nothing outside itself · `KernelSpec` proves all 21 exports · the gate builds and audits clean |
| test plumbing | no suite gives up waiting for the relay with a bare "relay did not start" |
| what a suite may touch | every relay path a suite supplies is under its own temp dir — all three that the relay writes, derived from `server/relay.mjs` · no suite reaches a host outside loopback |
| the recorded causes | each row in the table above names a claim that exists and still holds · every excluded suite's stated reason is true of it · `scripts/` delegations resolve to a tracked twin in the core run · `kant-debug.mjs` is tracked · carddebug spawns it rather than importing it |

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