# CLI file share, timed chat, and the Lean-checked capture — 2026-10-02

The browser could drop a file into a p2p room since the IPFS chunk store landed.
What it still could not do is be *driven* — an agent or a person in a terminal
had no way to announce a file, list the files in a room, fetch one, or reply to
one. This closes that gap, and then checks the whole round trip with Lean rather
than with a screenshot.

Three commits on `feat/cli-fileshare`, all on top of `feature/big-merge`:

| commit | what |
|---|---|
| `30ff25d0` | `drop` / `files` / `fetch` / `quote` on the CLI, plus `scripts/fileshare-capture.mjs` |
| `54d0d3ca` | `read` shows files, times, and resolved quotes |
| `f4ebe24f` | pin the capture browser with nix; fix `?ref=omain` and `?ref=omaster` |

Diff against `feature/big-merge`: 6 files, +842/-17.

## 1. The four commands

`scripts/kant-cli.mjs` grew four verbs. They need a room, so they behave like
`say` does and refuse without one.

```sh
# alice
node scripts/kant-cli.mjs --state a.json drop ./report.pdf
#   dropped report.pdf (312441B, 5 chunk(s))

node scripts/kant-cli.mjs --state a.json files
#   0: report.pdf (312441B, 5 chunk(s))

# bob
node scripts/kant-cli.mjs --state b.json files
node scripts/kant-cli.mjs --state b.json fetch 0 --out ./got.pdf
#   fetched report.pdf -> ./got.pdf (312441B)

node scripts/kant-cli.mjs --state b.json quote 0 'the graph on page 4 is wrong'
```

Three details are load-bearing, and each was a bug first:

**`drop` pins every chunk before it announces the manifest.** A manifest names
its chunks, so posting the announcement over a chunk that never landed would
tell the room about a file nobody can finish fetching. Chunks go to
`/room/<addr>/block/<witness>` first, the `kzfile` line last. A partial IPFS
pin is announced as relay-only rather than claimed as complete.

**Binary requests do not go through `send`.** `send` round-trips text; a chunk
pushed through it comes back as a UTF-8 string with every byte above 0x7f
replaced, which would fail the witness check on every chunk after the first.
Hence `sendBinary`, with `encoding: "buffer"` under the curl transport and
`application/octet-stream` over fetch. Under curl the `maxBuffer` is raised to
64 MiB, because the default truncates the chunk replies.

**`fetch` takes a witness, not a CID.** No CID is derivable from a witness
(`Kant.Bytes.digest` is four salted FNV-1a rounds, not a multihash), so
`takeFile` takes a fetcher keyed by witness and the caller resolves
witness -> CID. `decryptFile` derives the chunk index from *position in
`cids`* — there is no index field, so a one-chunk manifest can only ever mean
chunk 0. That is a property of the format, not something the CLI can work
around.

A MIME table names the file honestly, because the manifest commits to the
string and `application/octet-stream` for everything would be accurate and
useless.

## 2. What `read` has to show

`read` was quietly wrong twice.

`messagesOf` called `receive`, which parses `kzchat` only. A `kzat` stamped
line sat in `c.lines`, certified, and displayed as nothing — so a room where a
quote had just been posted read back empty. It is now
`receiveTimed(receive([], c.lines), c.lines)`: both forms, no line dropped.

The rendering printed the raw `kzquote:<witness>` prefix. That prefix is
machinery; a reader saw the wire format instead of what was said. `lineText`
now resolves the witness to a file name and renders

```
1a2b3c4d 2026-10-02 20:41:07 re: report.pdf — the graph on page 4 is wrong
```

and `read` also lists the files themselves, because a dropped file is a line
with no text to print and omitting it made a room where a file had just been
shared look empty:

```
[file 0] report.pdf (312441B, 5 chunk(s))
```

`--json` gains `at` (the sender's clock per message) and `files` beside the
existing `view`.

The untagged case matters: a plain `kzchat` line has no clock, and the first
attempt set `at = seq`, which filed every legacy message under 1970-01-01.
Untimed chat is now marked (`at: null`) rather than given a date nobody said,
and `byDay` has an `UNTITLED` bucket for it. `kzat` binds its tag in
`timedCore`, so a stamped line cannot be re-tagged as anything else.

## 3. The capture harness

`scripts/fileshare-capture.mjs` drives the real client at
`https://solana.solfunmeme.com/p2p-relay` through a whole share — open a room,
drop 700 KB, quote it, fetch it — and submits what it observed to the Aristotle
Lean service on `:9876`. It reuses the `gui2lean4` contract from
`~/projects/arist/gui2lean4`: same `gui2lean4-proof/v1` manifest, same
redact-before-write rule, same "a failed capture is not a proof" gate.

What is proved is not the UI. It is the invariant the file layer rests on, and
the theorems are stated over the *observed* values:

1. every chunk's witness is the digest of its **ciphertext**, so substitution
   is refused;
2. a manifest's witness is unchanged by whether it carries IPFS names, so an
   older peer's relay-only manifest still verifies;
3. a quote names the witness of the file it quotes, so a quote cannot be
   re-pointed;
4. the recorded pass count cannot exceed the number of checks run.

Because the witness is generated from the manifest, a run that observes
something different produces a witness that will not compile against the
manifest it ships with. A green Lean result with a red manifest is not
reachable.

Two operational notes, both learned the hard way:

* The Lean service **really compiles** `.lean` and reports other files INFO
  only, and it **rejects `namespace` and a doc comment before `section`**. The
  emitted witness is therefore plain top-level declarations with `--` line
  comments.
* Everything is redacted *before* it is written, never after. A room secret is
  32 bytes of hex and looks exactly like a UUID in the evidence.

Result, both modes, live:

```
headless   17/17   ALL PROOFS PASSED
headed     17/17   ALL PROOFS PASSED   (Nix Chromium 150.0.7871.186,
                                            1440x1800 VP8 WebM recorded)
```

## 4. The browser flake

`--headed` needs a full browser. Playwright's bundled download is only
`chrome-headless-shell`, which cannot open a window, and the previous fallback
reached for `/snap/bin/chromium` — a snap refresh and an unpinned version away
from failing.

`browser/flake.nix` pins nixpkgs' chromium instead: a store hash, no run-time
download, and it serves both modes. The script finds it by globbing
`/nix/store/*-chromium-*` (resolution order: `KANT_CHROMIUM` -> store glob ->
playwright full chromium -> system) so it survives a GC or an upgrade, and
records `{from, version}` in the manifest — a run that quietly used a
different engine would otherwise be indistinguishable from one that did not.
With no full browser at all, `--headed` **throws** rather than falling back to
headless.

`browser/` has to be a directory for the `path:` input, and git-tracked or
`path:` will not copy it. `browser/flake.nix` exposes
`packages.{chromium,fileshare-capture}` and a devShell; the top-level flake
re-exports them, so

```
$ nix eval .#packages.x86_64-linux
[ "chromium" "default" "fileshare-capture" "kant-pastebin" ]
```

## 5. `?ref=omain`

`flake.nix` had `?ref=omain` and `?ref=omaster`. Neither ref exists in the
mirrors — only `main` does — so every nix build on a GitHub runner died with

```
Cannot find Git revision '11707dc2…' in ref 'omain'
```

which is exactly what the red `Nix Build` check on
`main-meta-introspector/kant-zk-pastebin` has reported since the Oct 1 merges.
The same truncated word in both, so it looks like a find/replace over
main/master rather than one typo made twice. Fixed to `main`,
`nixos-unstable`, and `main`.

**This is not enough for upstream CI to go green.** The inputs are
`file:///mnt/data1/...` URLs, which a GitHub runner cannot resolve at all.
Turning the Nix check green upstream means pointing every input at a real
remote; that is a separate change and is not in this branch.

## 6. Verified

Against `https://solana.solfunmeme.com/p2p-relay`:

| | |
|---|---|
| `scripts/fileshare-capture.mjs` (headless) | 17/17, `ALL PROOFS PASSED` |
| `scripts/fileshare-capture.mjs --headed` | 17/17, `ALL PROOFS PASSED`, video recorded |
| CLI: alice drops 300 KB, bob lists, fetches, quotes | byte-identical sha256, both `read` the same room |
| `scripts/cli-test.mjs` | 77/77 |
| `web/test.mjs`, codec, net, file, crosscheck | all green |

Pre-existing failures, unchanged by this branch and confirmed on a clean tree:

* `web/page-test.mjs` 73/75 — two diagnostics-verdict failures
* `web/cli-page-test.mjs` 8/9 — its copy of the test DOM shim has no
  `querySelectorAll`, which `web/page-test.mjs` had added. The shim is
  copy-pasted into each test, and `1c921a46` fixed one copy of it
* `web/diagpage-test.mjs` 33/34
* `web/wasm-test.mjs` — needs `lake exe emitwasm dist` first
* `web/carddebug-test.mjs` — spawns `scripts/kant-debug.mjs`, which is not in
  the tree
