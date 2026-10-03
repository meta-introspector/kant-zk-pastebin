**Status:** pending

# 2026-09-24-pastebin-vs-pastebin-lean

## Role
Compare the running Rust pastebin to the Lean 4 port and write a report of
what the Lean corpus covers.

## Trees
| Side | Path |
|---|---|
| Rust (this checkout) | `/mnt/data1/kant/pastebin` |
| Lean port | `~/projects/pastebin-lean` |

**Note (2026-10-03):** `~/projects/pastebin-lean` main is now `bbac0ab`
(integration session) — it carries file-drop (kzfile codec, e2e), the
buffy p2p-wasm webapp, and hermetic p2p tests on top of the Lean corpus
this task compares. The comparison targets are unchanged; re-run the
report after any further Lean-side additions. See task
`2026-10-02-pastebin-lean-arist-integration`.

Do not edit either tree except the report script and its output directory.
`pastebin-lean` is an Aristotle checkout; leave its sources alone.

## Reflection tools (already in those trees)
- **Lean.** `lake exe emitdomain` walks the compiled `RequestProject`
  environment (name, kind, module, line, kernel axioms, `sorryAx`, deps).
  `lake exe packdomain --tables` turns that scan into `objects.csv`.
  Wrapper: `~/projects/pastebin-lean/scripts/domain-package.sh`.
  Needs a prior `lake build` of `RequestProject`.
- **Rust.** `cargo rustdoc -p kant-pastebin -- --output-format json` is the
  compiler's item index (`rustdoc` JSON). If that flag is rejected, the
  script falls back to `pub fn` / `pub struct` / `pub enum` / `pub trait`
  lines under `src/`.

Neither tool is reimplemented. The script only runs them and diffs the
name lists.

## Deliverable
`/mnt/data1/kant/pastebin/scripts/compare-pastebin-lean.sh`

```bash
bash scripts/compare-pastebin-lean.sh
# writes reports/pastebin-lean-compare/REPORT.md
# optional: OUT=... RUST=... LEAN=...
```

The report has: tool used on each side (or the fallback), counts, Rust
public items with no Lean name that contains the same identifier, and Lean
declarations whose module is in the README Rust→Lean map but whose stem
does not appear in the Rust dump.

## Out of scope
Proving missing items, porting code, rebuilding mathlib, committing the
report.
