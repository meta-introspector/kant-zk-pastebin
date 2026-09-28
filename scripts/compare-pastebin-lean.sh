#!/usr/bin/env bash
# Compare kant-pastebin (Rust) to ~/projects/pastebin-lean using the
# reflection tools those trees already have:
#   Lean: lake exe emitdomain + packdomain --tables  (objects.csv)
#   Rust: cargo rustdoc --output-format json, else a pub-item scan
# See ~/dotagents/tasks/2026-09-24-pastebin-vs-pastebin-lean/SYSTEM.md
set -euo pipefail

RUST="${RUST:-/mnt/data1/kant/pastebin}"
LEAN="${LEAN:-$HOME/projects/pastebin-lean}"
OUT="${OUT:-$RUST/reports/pastebin-lean-compare}"
mkdir -p "$OUT"

rust_note="pub-item scan (rg)"
lean_note="source scan (rg); emitdomain not run"

# --- Rust reflection -------------------------------------------------------
if command -v cargo >/dev/null && cargo rustdoc -p kant-pastebin --lib -- --output-format json \
    --output "$OUT/rustdoc" >/dev/null 2>"$OUT/rustdoc.err"; then
  rust_note="cargo rustdoc --output-format json"
  python3 - "$OUT/rustdoc" "$OUT/rust-items.txt" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
docs = list(root.rglob("*.json"))
# rustdoc writes <crate>.json at the output root
names = []
for p in docs:
    data = json.loads(p.read_text())
    idx = data.get("index", {})
    for item in idx.values():
        if not isinstance(item, dict):
            continue
        kind = item.get("kind")
        if kind not in ("function", "struct", "enum", "trait", "module", "constant", "typedef"):
            continue
        name = (item.get("name") or "").strip()
        if name and not name.startswith("_"):
            names.append(f"{kind}\t{name}")
pathlib.Path(sys.argv[2]).write_text("\n".join(sorted(set(names))) + ("\n" if names else ""))
print(len(set(names)))
PY
else
  python3 - "$RUST/src" "$OUT/rust-items.txt" <<'PY'
import pathlib, re, sys
pat = re.compile(r"^\s*pub(?:\([^)]*\))?\s+(?:async\s+)?(?:fn|struct|enum|trait|const|type|static)\s+([A-Za-z_][A-Za-z0-9_]*)", re.M)
names = set()
for p in pathlib.Path(sys.argv[1]).rglob("*.rs"):
    text = p.read_text(errors="replace")
    for m in pat.finditer(text):
        names.add("item\t" + m.group(1))
pathlib.Path(sys.argv[2]).write_text("\n".join(sorted(names)) + ("\n" if names else ""))
print(len(names))
PY
fi

# --- Lean reflection -------------------------------------------------------
emit="$LEAN/.lake/build/bin/emitdomain"
pack="$LEAN/.lake/build/bin/packdomain"
if [[ -x "$emit" && -x "$pack" ]]; then
  lean_note="emitdomain + packdomain --tables"
  "$emit" "$OUT/corpus-scan.kant" RequestProject
  "$pack" --tables "$OUT/corpus-scan.kant" "$OUT/domain"
  # objects.csv: first column is the declaration name (see domain docs)
  if [[ -f "$OUT/domain/objects.csv" ]]; then
    python3 - "$OUT/domain/objects.csv" "$OUT/lean-items.txt" <<'PY'
import csv, pathlib, sys
rows = list(csv.reader(open(sys.argv[1])))
# header may or may not exist; keep the column that looks like a dotted name
names = []
start = 1 if rows and any("name" in c.lower() for c in rows[0]) else 0
name_col = 0
if start == 1:
    for i, c in enumerate(rows[0]):
        if c.lower() in ("name", "decl", "declaration"):
            name_col = i
            break
for row in rows[start:]:
    if len(row) <= name_col:
        continue
    n = row[name_col].strip()
    if n:
        names.append(n)
pathlib.Path(sys.argv[2]).write_text("\n".join(names) + ("\n" if names else ""))
print(len(names))
PY
  fi
else
  python3 - "$LEAN/RequestProject" "$OUT/lean-items.txt" <<'PY'
import pathlib, re, sys
pat = re.compile(r"^(?:def|theorem|abbrev|structure|inductive|opaque|class)\s+([A-Za-z_][A-Za-z0-9_']*)", re.M)
names = set()
root = pathlib.Path(sys.argv[1])
for p in root.rglob("*.lean"):
    rel = p.relative_to(root).with_suffix("")
    mod = "RequestProject." + ".".join(rel.parts)
    text = p.read_text(errors="replace")
    for m in pat.finditer(text):
        names.add(f"{mod}.{m.group(1)}")
pathlib.Path(sys.argv[2]).write_text("\n".join(sorted(names)) + ("\n" if names else ""))
print(len(names))
PY
fi

python3 - "$OUT" "$rust_note" "$lean_note" "$RUST" "$LEAN" <<'PY'
import pathlib, sys
out, rust_note, lean_note, rust_root, lean_root = sys.argv[1:]
out = pathlib.Path(out)
rust = [l.split("\t", 1)[-1] for l in (out / "rust-items.txt").read_text().splitlines() if l.strip()]
lean = [l.strip() for l in (out / "lean-items.txt").read_text().splitlines() if l.strip()]
lean_stems = {n.split(".")[-1].replace("'", "").lower() for n in lean}

def stem(n):
    return n.split(".")[-1].replace("'", "").lower()

missing_in_lean = sorted({n for n in rust if stem(n) not in lean_stems})
rust_stems = {stem(n) for n in rust}
# Lean decls whose last segment is not a Rust item — sample, cap the list
lean_only = sorted({n for n in lean if stem(n) not in rust_stems})

lines = []
lines.append("# Pastebin Rust vs Lean comparison")
lines.append("")
lines.append(f"- Rust tree: `{rust_root}`")
lines.append(f"- Lean tree: `{lean_root}`")
lines.append(f"- Rust tool: {rust_note} ({len(rust)} names)")
lines.append(f"- Lean tool: {lean_note} ({len(lean)} names)")
lines.append("")
lines.append(f"## Rust names with no Lean stem ({len(missing_in_lean)})")
lines.append("")
for n in missing_in_lean[:200]:
    lines.append(f"- `{n}`")
if len(missing_in_lean) > 200:
    lines.append(f"- … {len(missing_in_lean) - 200} more")
lines.append("")
lines.append(f"## Lean names with no Rust stem ({len(lean_only)})")
lines.append("")
lines.append("Most of these are theorems. Listed only when the stem is absent from the Rust dump.")
lines.append("")
for n in lean_only[:200]:
    lines.append(f"- `{n}`")
if len(lean_only) > 200:
    lines.append(f"- … {len(lean_only) - 200} more")
lines.append("")
(out / "REPORT.md").write_text("\n".join(lines) + "\n")
print(out / "REPORT.md")
print(f"rust={len(rust)} lean={len(lean)} rust_without_lean_stem={len(missing_in_lean)}")
PY
