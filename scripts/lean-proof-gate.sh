#!/usr/bin/env bash
# lean-proof-gate.sh — build the Lean proof with gokujo, Mathlib-free.
#
#   scripts/lean-proof-gate.sh            # the gate: scan + build + holes + axioms
#   scripts/lean-proof-gate.sh --json     # machine-readable
#   scripts/lean-proof-gate.sh --clean    # drop the build cache first
#
# Why this is its own script and not a `lake build`: the Lean tree imports
# nothing outside core Lean 4, so `LEAN_PATH` is deliberately *unset*. There is
# no `lakefile`, no `elan`, and no Mathlib: `gokujo` supplies the dependency
# graph, the build order, and the hole and axiom audits in one command, and
# exits non-zero if any of them fail.
#
# Why the version is pinned here: `lean-toolchain` says `v4.28.0`, but the
# `lean` and `lake` on this machine's PATH are 4.30.0 and there is no `elan` to
# reconcile them. The nix store path below is 4.28.0, verified with `lean
# --version`. If it is gone, the gate fails loudly rather than silently
# checking the proofs with a different compiler.
#
# The measurement that shaped this file: with Mathlib on `LEAN_PATH`, a single
# module costs >400s to elaborate (`import Mathlib` alone did not finish in
# 401s) and the 26-module closure never produced a single olean in 560s.
# Mathlib-free, the same closure is 13 modules and `gokujo check` finishes in
# ~10.5s cold and ~2.7s warm. That is why the build can sit in `npm run verify`.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$ROOT/lean-gate"

LEAN_VERSION="4.28.0"
LEAN_STORE="/nix/store/75c91mcn5ric5m141r7hbf3hf8f12r7x-lean4-$LEAN_VERSION/bin"
GOKUJO_BIN="${GOKUJO_BIN:-/home/mdupont/.cache/aristotle-manager/bin/gokujo}"

die() { echo "lean-proof-gate: $*" >&2; exit 1; }

[ -d "$GATE/RequestProject" ] || die "no $GATE/RequestProject -- the proof tree is missing"

# The toolchain. Both are reported by name, because "command not found" three
# layers down in a build log is not a diagnosis.
[ -x "$LEAN_STORE/lean" ] || die "Lean $LEAN_VERSION not found at $LEAN_STORE/lean.
  This gate pins the toolchain that lean-gate/RequestProject/lean-toolchain
  asks for. Install it, or point LEAN_STORE at an equivalent."
"$LEAN_STORE/lean" --version | grep -q "version $LEAN_VERSION," \
  || die "$LEAN_STORE/lean is not Lean $LEAN_VERSION: $("$LEAN_STORE/lean" --version)"

[ -x "$GOKUJO_BIN" ] || die "gokujo not found at $GOKUJO_BIN (override with GOKUJO_BIN=...)"
command -v cadical >/dev/null 2>&1 || [ -x "$LEAN_STORE/cadical" ] \
  || die "no cadical on PATH; gokujo needs it to discharge the build goals"

JSON=""
CLEAN=""
for arg in "$@"; do
  case "$arg" in
    --json) JSON=1 ;;
    --clean) CLEAN=1 ;;
    *) die "unknown argument $arg" ;;
  esac
done

[ -n "$CLEAN" ] && rm -rf "$GATE/.gokujo"

# No LEAN_PATH: the point of the gate is that these proofs need nothing but
# core Lean. An inherited LEAN_PATH would let a stray `import Mathlib` pass by
# paying for it, which is exactly the >400s-per-module cost this tree removes.
unset LEAN_PATH
export PATH="$LEAN_STORE:$PATH"

cd "$GATE"

if [ -n "$JSON" ]; then
  exec "$GOKUJO_BIN" check --json RequestProject
fi

"$GOKUJO_BIN" check RequestProject