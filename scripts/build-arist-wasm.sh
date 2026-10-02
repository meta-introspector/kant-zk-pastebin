#!/usr/bin/env bash
# scripts/build-arist-wasm.sh — rebuild web/aristotle_wasm.js + _bg.wasm from the
# vendored crate (experiments/aristotle-wasm/).
#
# Path A (full): cargo with wasm32-unknown-unknown + wasm-bindgen-cli matching
#                the crate's wasm-bindgen version (see Cargo.lock).
# Path B (glue-only, what this host can do today): wasm-bindgen-cli over the
#                prebuilt blob in experiments/aristotle-wasm/prebuilt/ — the
#                rust→wasm step was already done; bindgen only re-derives the JS.
set -euo pipefail
cd "$(dirname "$0")/.."

BINDGEN="${WASM_BINDGEN:-$HOME/.cargo/bin/wasm-bindgen}"
CRATE=experiments/aristotle-wasm
OUT=web

if command -v rustup >/dev/null 2>&1 && rustup target list --installed 2>/dev/null | grep -q wasm32-unknown-unknown; then
  echo "== building $CRATE for wasm32-unknown-unknown =="
  (cd "$CRATE" && cargo build --release --target wasm32-unknown-unknown)
  BLOB="$CRATE/target/wasm32-unknown-unknown/release/aristotle_wasm.wasm"
elif [[ -f "$CRATE/prebuilt/aristotle_wasm.wasm" ]]; then
  echo "== cargo/wasm target unavailable — using prebuilt blob (glue-only rebuild) =="
  BLOB="$CRATE/prebuilt/aristotle_wasm.wasm"
else
  echo "no wasm toolchain and no prebuilt blob" >&2
  exit 1
fi

[[ -x "$BINDGEN" ]] || { echo "wasm-bindgen-cli not found at $BINDGEN" >&2; exit 1; }
"$BINDGEN" --version
"$BINDGEN" --target web --out-dir "$OUT" "$BLOB"
echo "== wrote $OUT/aristotle_wasm{.js,_bg.wasm} =="
node -e "import('./web/aristotle_wasm.js').then(()=>console.log('glue imports cleanly (node ESM)')).catch(e=>{console.error('glue import failed:',e.message);process.exit(1)})"
