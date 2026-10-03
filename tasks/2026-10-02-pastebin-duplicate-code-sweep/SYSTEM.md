# Task: pastebin-duplicate-code-sweep

**Status:** open
**Project:** kant/pastebin, branch `feat/cli-fileshare`
**Found:** 2026-10-02, by keyword and by content hash

Four layers of duplication, largest first. The first one is not a style
problem — it is a mirror directory, and it has already caused a bug.

## 1. `scripts/` is a byte-identical mirror of `web/` (29 files)

29 of the 58 tracked files in `scripts/` have a byte-identical twin in `web/`,
verified by sha256. Nothing references the `scripts/` copy: not the workflows,
not `package.json`, not the docs. `scripts/` also holds 23 genuinely unique
files (build, deploy, capture tooling) — it is a real directory that someone
copied `web/` into.

The twins include 12 **library modules**, not just tests: `kantzk.mjs`,
`kant-codec.mjs`, `kant-uucp.mjs`, `kant-flow.mjs`, `kant-pass.mjs`,
`kant-diag.mjs`, `kant-carddebug.mjs`, `kant-share.mjs`, `kant-sharelog.mjs`,
`kant-site.mjs`, `kant-qr.mjs`, `kant-kernel-embedded.mjs`, plus 16 test files.

**This has already bitten.** `1c921a46` fixed `querySelectorAll` in one copy of
the test DOM shim. The other copy still lacks it, which is why
`web/cli-page-test.mjs` fails today (task PB-10). A fix applied to one twin is
a fix that did not happen.

## 2. The test harness is copy-pasted into every test file

Distinctive lines (≥45 chars) appearing in more than one file:

| repeated | copies | what |
|---|---|---|
| `console.log(\`${checks - fail.length}/${checks} checks passed\`)` | 10 | result summary |
| `for (const f of fail) console.error(\`FAIL: ${f}\`)` | 10 | failure report |
| `ok(\`${name} (got …, want …)\`, got === want)` | 8 | assertion helper |
| `const here = dirname(fileURLToPath(import.meta.url))` | 6 | path setup |
| `const ok = (name, cond) => { checks += 1; … }` | 6 | assertion helper |
| `const check = (name, fn) => { … }` | 5 | assertion helper |
| `const eqBytes = (a, b) => a.length === b.length && …` | 5 | byte compare |
| `click() { if (this.onclick) return this.onclick(); }` | 4 | DOM shim |
| `getElementById: (id) => elements.get(id) ?? null` | 4 | DOM shim |
| `Object.defineProperty(globalThis, "navigator", {` | 4 | DOM shim |
| `getItem: (k) => (local.has(k) ? local.get(k) : null)` | 4 | DOM shim |

And `startRelay` is **byte-identical** in `web/cli-page-test.mjs`,
`web/cli-test.mjs` and `web/diag-test.mjs` once the argv line is normalised
(same md5).

Extract one `web/test-harness.mjs` exporting `ok`/`eq`/`check`/`eqBytes`/`here`,
one `web/dom-shim.mjs`, and one `startRelay`. Every test then gets the same
shim, so PB-10's class of bug cannot recur in one copy and not the other.

## 3. Rust: one identical triple, one name with two bodies, one dead file

* **`html_escape` is byte-identical in three files** — `src/gallery.rs`,
  `src/handlers.rs`, `src/view.rs` (same md5). Move it to one place.
* **`slugify` has three definitions and two behaviours.** `src/api.rs` and
  `src/tagging.rs` are identical apart from `fn` vs `pub fn`. `src/main_old.rs`
  is a *different algorithm* — it keeps `-`, turns whitespace into `-`, and
  drops other characters instead of substituting `_`. Two different slug
  formats from one name is a trap for whoever calls the wrong one.
* **`src/main_old.rs` is 881 dead lines.** `cargo metadata` does not list it as
  a target and nothing declares it as a module. It also accounts for 8 of the
  duplicated lines `handlers.rs` shares with other files.
* `handlers.rs` shares 15 lines with `gallery.rs`, 11 with `view.rs`, 8 with
  `main_old.rs`.

Note `save_identity` / `save_avatar` / `list_avatars` appear twice on purpose:
the `Storage` impl and the `MeshState` proxies that delegate to it (PR #5).
Leave those.

## 4. Not duplication, despite the keyword search finding it

Same-named exports that are genuinely different functions, and should not be
unified:

* `roomOf` — `kant-net.mjs` takes a secret and returns a witness;
  `kant-carddebug.mjs` takes a code and returns a room.
* `shareUrl` — `kant-site.mjs` composes `addressUrl`; `kantzk.mjs` is
  `base + "#" + envelopeEncode(e)`.
* `inviteUrl`, `shareText`, `mentions`, `thread`, `explain` — different
  purposes in each file.

`view`, `roomOf` etc. re-exported from `web/kant-cli.mjs` are re-exports, not
redefinitions.

## Suggested order

1. Delete the 29 twins in `scripts/` and fix the one doc reference
   (`docs/CLI_FILESHARE_2026-10-02.md` names `scripts/cli-page-test.mjs`).
   Smallest change, removes a whole failure mode.
2. `html_escape` → one definition. Ten minutes.
3. Delete `src/main_old.rs`, or move it to `archive/` — it is not a target.
4. Extract the test harness and DOM shim. Largest, and the one that pays back
   by making PB-10 impossible to half-fix.

## Verify

```sh
cd /mnt/data1/kant/pastebin-cli-fileshare

# 1: no byte-identical twin pairs left
git ls-files | grep -vE '^(node_modules|data)/' | xargs sha256sum | awk '{print $1}' | sort | uniq -d

# 2/3: rust still builds and tests pass (see docs/RUST_TESTS.md for the glibc)
cargo check --lib

# 4: the suite still runs
node web/cli-test.mjs        # 77/77
node web/cli-page-test.mjs   # 9/9 once the shim is shared (PB-10)
```
