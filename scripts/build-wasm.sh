#!/usr/bin/env bash
# Build the Lean core to WebAssembly.
#
# This script is scaffolding: it documents and automates the Lean -> C -> wasm
# path described in docs/WASM-AND-NETWORK.md. It has NOT been executed
# successfully in this repository, because the environment this port was
# developed in has no emscripten toolchain. It checks for its prerequisites and
# exits with a clear message rather than pretending to succeed.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="$root/build/wasm"

missing=()
command -v emcc >/dev/null 2>&1 || missing+=("emcc (emscripten)")
command -v lake >/dev/null 2>&1 || missing+=("lake (Lean 4)")
[ -n "${LEAN_WASM_SYSROOT:-}" ] || missing+=("LEAN_WASM_SYSROOT (Lean runtime cross-built for wasm32-emscripten)")

if [ "${#missing[@]}" -ne 0 ]; then
  echo "cannot build wasm; missing prerequisites:" >&2
  for m in "${missing[@]}"; do echo "  - $m" >&2; done
  cat >&2 <<'EOF'

To satisfy them:
  1. install emscripten          https://emscripten.org/docs/getting_started/
  2. cross-build the Lean runtime for wasm32-emscripten from the Lean 4 source
     tree (cmake with Emscripten.cmake as the toolchain file), and point
     LEAN_WASM_SYSROOT at the resulting prefix; its lib/ must contain
     libleanrt.a and libleangmp.a built by the SAME toolchain version as the
     lean that emits the C below.

See docs/WASM-AND-NETWORK.md for the design and for the golden vectors any
build must reproduce.
EOF
  exit 1
fi

echo ">> lake build (emits .olean and C for the Kant modules)"
cd "$root"
lake build

mkdir -p "$out"

echo ">> collecting generated C"
mapfile -t csrc < <(find "$root/.lake/build/ir" \( -name 'Kant*.c' -o -name 'RequestProject*.c' \) | sort)
if [ "${#csrc[@]}" -eq 0 ]; then
  echo "no generated C found under .lake/build/ir; nothing to compile" >&2
  exit 1
fi

# Exported surface: the pure computable core. See docs/WASM-AND-NETWORK.md section 1.
exports='["_kant_witness","_kant_nested_cid","_kant_dasl_hex","_kant_orbifold",
          "_kant_escape","_kant_frames","_kant_reassemble",
          "_kant_embed","_kant_extract",
          "_kant_godel","_kant_ungodel",
          "_kant_circuit_encode","_kant_circuit_decode",
          "_malloc","_free"]'

echo ">> emcc"
emcc "${csrc[@]}" \
  -I "$LEAN_WASM_SYSROOT/include" \
  -L "$LEAN_WASM_SYSROOT/lib" \
  -lleanrt -lleangmp \
  -O2 \
  -s WASM=1 \
  -s MODULARIZE=1 \
  -s EXPORT_ES6=1 \
  -s ALLOW_MEMORY_GROWTH=1 \
  -s EXPORTED_FUNCTIONS="$exports" \
  -s EXPORTED_RUNTIME_METHODS='["ccall","cwrap","HEAPU8"]' \
  -o "$out/kantzk.mjs"

echo ">> built $out/kantzk.mjs and $out/kantzk.wasm"
echo ">> now check it against the Lean golden vectors:"
echo "   KANTZK_IMPL=$out/kantzk.mjs node web/test.mjs"
