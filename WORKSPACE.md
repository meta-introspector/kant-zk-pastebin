# Workspace Integration Notes

## Overview

This repo is a Cargo workspace that unifies several plugin submodules that each
originally had their own `[workspace]` roots. Getting them to coexist required
a series of fixes documented here.

---

## Workspace Members

```
.                                          # kant-pastebin (main binary)
pastebin-wasm/                             # WASM build
plugins/html5ever/{tendril,web_atoms,markup5ever,html5ever,rcdom,xml5ever}
plugins/html5ever/cssparser/{.,macros,color}
plugins/oxc/crates/{oxc_allocator,oxc_ast,oxc_ast_macros,oxc_ast_visit,
                    oxc_data_structures,oxc_diagnostics,oxc_ecmascript,
                    oxc_estree,oxc_parser,oxc_regular_expression,
                    oxc_span,oxc_str,oxc_syntax}
```

---

## Problems Solved

### 1. `edition.workspace = true` conflicts

html5ever and oxc crates inherit `edition` from their own workspace root.
When pulled into ours, they need our `[workspace.package]` to define all
fields they inherit (`edition`, `description`, `homepage`, `keywords`,
`categories`, `rust-version`, `authors`, `license`, `repository`).

**Fix:** `[workspace.package]` in root `Cargo.toml` defines all of these.
oxc requires `edition = "2024"` so that is the workspace default.
html5ever crates were given explicit `edition = "2021"` since they use
`ref` patterns and other syntax not valid in 2024.

### 2. cssparser had its own `[workspace]`

cssparser's `Cargo.toml` contained a `[workspace]` block making it a
workspace root, which conflicts with ours.

**Fix:** Removed the `[workspace]` block from `plugins/html5ever/cssparser/Cargo.toml`
and added cssparser + its sub-crates (`macros`, `color`) as explicit members
in the root workspace.

### 3. `zos-circuit-optimizer` vendored `erdfa-dasl` collision

`plugins/zos-circuit-optimizer/vendor/erdfa-dasl/` is a stale vendor copy of
`plugins/erdfa-dasl/`. Cargo pulled both into the workspace causing a
"two packages named erdfa-dasl" error.

**Fix:** Changed `zos-circuit-optimizer`'s dep to point directly at
`../erdfa-dasl` (the canonical copy) instead of its vendor dir.

### 4. `erdfa-dasl/src/dasl.rs` was a broken symlink

`plugins/erdfa-dasl/src/dasl.rs` was a symlink to `../../src/dasl.rs`
(i.e. the main crate's `src/dasl.rs`). The symlink was broken in the
build environment.

**Fix:** Replaced with a real file copy. `src/dasl.rs` is now the source
of truth; `plugins/erdfa-dasl/src/dasl.rs` is a copy. Keep them in sync
manually or via `cp src/dasl.rs plugins/erdfa-dasl/src/dasl.rs`.

### 5. Missing functions in `erdfa-dasl`

The vendor copy had functions the canonical lacked:
- `orbifold_coords_full(n: usize) -> Vec<u64>` — used by all parser bins
- `orbifold_distance(a, b) -> u64` — used by zos-circuit-optimizer
- `distance_from_origin(coords) -> u64`

**Fix:** Added all three to `src/dasl.rs` (and synced to the plugin copy).

### 6. oxc 0.126 API changes in `js_interpreter.rs`

- `oxc_ast::visit` and `oxc_ast::Visit` moved to `oxc_ast_visit` crate
- `BindingPatternKind` renamed to `BindingPattern` (it is the enum directly)
- `declarator.id.kind` → `declarator.id` (no `.kind` field)

**Fix:** Updated imports and match arm in `src/bin/js_interpreter.rs`.

### 7. Missing `workspace.dependencies`

oxc and html5ever crates use `dep.workspace = true` for many external crates.
These must all be declared in our `[workspace.dependencies]`.

**Fix:** `fix-workspace-deps.sh` — iteratively runs `cargo check`, extracts
missing dep names, looks them up in `plugins/oxc/Cargo.toml` or
`plugins/html5ever/Cargo.toml`, and appends them to `Cargo.toml`.
Run it again any time a new oxc/html5ever crate is added to the workspace.

---

## Parser Bins

| Binary | Source | Input | Make target |
|---|---|---|---|
| `js_parser` | `src/bin/js_parser.rs` | `.js` file | `make test-js` |
| `js_interpreter` | `src/bin/js_interpreter.rs` | hardcoded tests | `make test-js` |
| `html_parser` | `src/bin/html_parser.rs` | `.html` file | `make test-html` |
| `css_parser` | `src/bin/css_parser.rs` | `.css` file | `make test-css` |
| `test_generator` | `src/bin/test_generator.rs` | — | `make test-generators` |

Run all: `make test-bins`

Test fixtures are in `test-fixtures/` (`sample.js`, `sample.html`, `sample.css`).

All parsers annotate tokens/nodes with orbifold coordinates derived from
Monster group primes via `erdfa_dasl::orbifold_coords_full`.

---

## Fuzz Corpus

`test_generator` produces 194 seed files in `fuzz/corpus/test_NNN.json`,
one per Monster group irreducible representation. Used as AFL++ seed corpus.

---

## Maintenance Notes

- Do not use symlinks for source files — cargo does not reliably follow them.
- After adding a new oxc/html5ever workspace member, run `bash fix-workspace-deps.sh`.
- `src/dasl.rs` and `plugins/erdfa-dasl/src/dasl.rs` must be kept in sync manually.
- `workspace.lints` is defined in root `Cargo.toml` to satisfy oxc crates that
  inherit `lints.workspace = true`.
