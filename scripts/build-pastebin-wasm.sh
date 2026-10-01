#!/usr/bin/env bash
# build-pastebin-wasm.sh — compile the pastebin core (Rust) to wasm and
# regenerate the browser glue.
#
#   scripts/build-pastebin-wasm.sh
#
# Steps: cargo build --target wasm32-unknown-unknown, wasm-bindgen --target web
# into web/, then the crosscheck — the wasm and the pure-JS CID path must
# agree byte-for-byte or this exits nonzero (CI treats that as a failed build).
set -euo pipefail
cd "$(dirname "$0")/.."

CRATE=pastebin-wasm
BINDGEN="${WASM_BINDGEN:-$HOME/.cargo/bin/wasm-bindgen}"

[[ -x "$BINDGEN" ]] || { echo "wasm-bindgen-cli not found at $BINDGEN (cargo install wasm-bindgen-cli --version 0.2.129)" >&2; exit 1; }

echo "== building $CRATE for wasm32-unknown-unknown =="
(cd "$CRATE" && cargo build --release --target wasm32-unknown-unknown)

BLOB="$CRATE/target/wasm32-unknown-unknown/release/pastebin_wasm.wasm"
echo "== bindgen -> web/ =="
"$BINDGEN" --target web --out-dir web "$BLOB"

echo "== crosscheck (wasm must equal the JS/kubo contract) =="
node scripts/wasm-crosscheck.mjs

echo "== wrote web/pastebin_wasm{.js,_bg.wasm} =="
