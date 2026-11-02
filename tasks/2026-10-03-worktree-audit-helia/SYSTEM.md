# Task: worktree-audit-helia

- **Name:** worktree-audit-helia
- **Priority:** P1
- **Area:** kant-zk, repo hygiene, helia, ipfs
- **Status:** open — nothing lost, one file broken, one task file inaccurate
- **Created:** 2026-10-03
- **Related:** PB-32 / `2026-10-03-libp2p-prior-work-triage`, PB-35
- **Tags:** kant-zk, repo-hygiene, helia, ipfs, git

## Scope

Full audit of all 17 worktrees of the pastebin repo
(`git worktree list`), plus all local-only branches, plus every dirty file.
Audit only — no destructive action taken.

## Headline

**Nothing is lost. One file is syntactically broken, and one task file claims
work that does not exist.**

## 1. `/mnt/data1/kant/pastebin` — `feature/big-merge` — BROKEN FILE

`web/kant-ipfs.mjs` is modified and uncommitted, and **does not parse**:

```
/mnt/data1/kant/pastebin/web/kant-ipfs.mjs:27
  }
  ^
SyntaxError: Unexpected token '}'
```

The diff is a half-applied refactor. It deletes the Rust/wasm core block
(`wasmCore`, `wasmTried`, `wasmOnce()` — 29 lines) and replaces it with
`import { heliaCat, heliaAdd, heliaNode } from "./kant-helia.mjs";` while
leaving an orphaned `}` and a dangling `return wasmCore;`. Net: **1 insertion,
29 deletions.**

**This is not on any branch and not pushed.** `origin/feature/big-merge` is at
`b1c42bd9` and its committed `web/kant-ipfs.mjs` is **valid** (`node --check`
passes). So the breakage is confined to this one working copy.

**Why it matters:** this is the primary worktree on the main integration
branch. Any local test run, any `nix develop` invocation, any editor reload that
picks up the working-tree version sees a syntax error in a core module — the one
that computes the CIDv1 values the whole IPFS layer depends on. It fails at
parse time, so it fails loudly, which is the one mercy here.

**Recovery is complete and verified:** the *valid* version of this file's
intended content exists at `wip/deploy-checkout-20261003:web/kant-ipfs.mjs`
(`node --check` passes there too). The working-copy edit is strictly *less*
complete than that branch, not more. So the fix is `git checkout --
web/kant-ipfs.mjs` to restore the committed valid version, and take the helia
work from `wip/deploy-checkout-20261003` if it is wanted.

Left in place pending a decision — restoring a file is a (small) destructive
action and the operator did not ask for it.

## 2. `tasks/helia-integration/SYSTEM.md` — untracked, and factually wrong

Untracked in the same worktree, on **no branch anywhere** (`git log --all --
tasks/helia-integration/` is empty). It is a real piece of thinking and worth
keeping, but its claims do not survive checking:

| Task file claims | Actual |
|---|---|
| `web/kant-helia.mjs` — "done, rewritten" | **exists only on `wip/deploy-checkout-20261003`**; not in this worktree, not on `feature/big-merge`, `main`, `feature/lean`, or `dev/integrated` |
| `web/helia-vendor/{package.json,build.js}` — "done" | same: only on `wip/deploy-checkout-20261003` |
| `web/kant-ipfs.mjs` — "done, syntax fixed, `node --check` passes" | **the working copy does not parse** |
| "`flake.nix` — todo, attrset malformed" | flake.nix shows clean in `git status`; unverified whether `heliaVendor` was ever added |
| 6 of 6 "Accomplished" boxes ticked | at most 3 are true, and the syntax one is now false |

So the checklist overstates its own state. The genuinely useful content is the
**design** — pre-computed CIDs via `blockstore.put(CID.parse(cid), bytes)` +
`pins.add(cid)` rather than `content.add()`, so Helia can never invent a CID
that drifts from kubo; dial failures non-fatal with gateway fallback; and the
note that `web/` has no bundler, so vendored ESM must be hand-wired.

**Those three design decisions are worth keeping and are not recorded anywhere
else.** The status table is not.

**Note the irony worth recording:** this task file's central claim about
Helia — "Helia must never call `content.add()`" — is exactly the class of bug
this session has been chasing everywhere else (a second CID source of truth
drifting from the first). It identified the right thing and then lost track of
whether the code existed.

## 3. The helia work exists, on exactly one branch

```
wip/deploy-checkout-20261003        helia files=3   (web/kant-helia.mjs, helia-vendor/{build.js,package.json})
every other branch (incl. main, feature/big-merge, feature/lean, dev/integrated)   0
```

`wip/deploy-checkout-20261003` is pushed (`origin/` has it). So the work is
safe and recoverable — **but it is on the same `wip/*` branch that misled me
about libp2p.**

## 4. The `wip/*` branch problem, again and worse

This is now the third time a `wip/*` branch has produced a wrong conclusion:

- **libp2p:** I said "369 lines, never executed" from `wip/deploy-checkout-20261003`; reality was 690 lines + 45 tests on `feature/big-merge` (PR #9).
- **helia:** I said `kant-helia.mjs` and `helia-vendor/` were "unmerged, stranded"; reality is they are **only** there, and nowhere else.
- **Both directions are wrong.** A `wip/*` snapshot is neither a reliable index of current work nor a reliable index of abandoned work. It is a snapshot.

**`wip/deploy-checkout-20261003` is now the single most misleading branch in
the repo.** It is the sole home of the helia work, and the source of a stale
369-line libp2p copy that would have caused a 690-line tested implementation to
be discarded. It should be mined for anything worth keeping and then either
folded into a real branch or deleted with a note.

## 5. `/tmp/pb-clean` — detached, superseded, safe to delete

Detached at `b23c518f`, with `src/libp2p_frames.rs` untracked and `src/lib.rs`
modified (+1 line, `pub mod libp2p_frames;`).

Both are **older** than what is committed: `feature/big-merge:src/libp2p_frames.rs`
is **648 lines** against this worktree's **547**, and the extra 101 lines in the
committed version are the `PayloadAndNonce` variant — a `FrameError` rejecting
frames that carry both a payload and a nonce, with the reason spelled out:

> *"The wire format has no payload-length field, so a frame carrying both a
> payload and a nonce would be undecodable. Refuse rather than emit bytes that
> only happen to work because no caller does this today."*

That is a hardening commit the detached worktree predates. **Nothing unique is
here.** Safe to remove.

## 6. Everything else is clean

- **All 12 pushed branches are exactly in sync** with `origin` — `behind=0
  ahead=0` on every one.
- **4 of 5 local-only branches are fully contained** in `origin/feature/big-merge`
  or `origin/fix/mesh-state-methods`, so deleting them loses nothing:
  `diagnose/wasm-p2p`, `fix/mesh-rebuild`, `wasm-port/js-only`, `push/big-merge`.
- **`fix/nora-vendor-merge` (`a86e6df5`) is the only genuinely local-only
  branch** — contained in nothing else. Still deliberately unpushed: it commits
  `spool/svg2anim-jobs/` (21,486 files) and its only real change is already in
  main.
- Two worktrees are "dirty" with **only `server/.wrangler/`** — wrangler's local
  state dir, which correctly is not ignored. Not work, but it is why
  `git status` reads dirty; worth adding to `.gitignore` so real dirt is
  visible.
- 3 submodules show as modified with **0 line changes** (`cleanssl`,
  `erdfa-publish-investigation`, `ssl-test`) — dirty submodule pointers, not
  content edits.

## Recommended actions, in order

1. **Restore `web/kant-ipfs.mjs`** in `/mnt/data1/kant/pastebin` — it is a
   syntax error in a core module in the primary worktree.
   `git checkout -- web/kant-ipfs.mjs`. Take helia from
   `wip/deploy-checkout-20261003` if wanted.
2. **Commit `tasks/helia-integration/SYSTEM.md`** somewhere tracked, with the
   status table corrected to match reality — the design notes are worth keeping,
   the ticks are not.
3. **Mine `wip/deploy-checkout-20261003`** for the helia work, then delete the
   stale libp2p copy from it and delete the branch. It is actively misleading.
4. **Delete `/tmp/pb-clean`** — superseded, nothing unique.
5. **`git worktree prune`** after that; the 17-worktree count is mostly
   abandoned checkouts, which is how this drift went unnoticed.
6. **Add `server/.wrangler/` to `.gitignore`** so real dirt is not masked.
7. Delete the 4 fully-contained local-only branches.

None of these were done — all are destructive or irreversible enough to want
explicit approval, and the operator asked for a review, not a cleanup.