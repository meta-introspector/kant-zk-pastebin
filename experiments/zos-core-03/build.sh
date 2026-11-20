#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
out="$(realpath -m "${1:?fresh output path required}")"
mkdir "$out"
export CARGO_TARGET_DIR="$out/target"
export CARGO_NET_OFFLINE=true
export LC_ALL=C
rustc +stable -Vv
node --version
openssl version
cargo +stable tree --offline --locked --target wasm32-unknown-unknown
cargo +stable tree --offline --locked --target x86_64-unknown-linux-gnu
RUSTFLAGS="-D warnings --remap-path-prefix=$PWD=/zos-core03" \
    cargo +stable build --offline --locked --release --bin native
RUSTFLAGS="-D warnings --remap-path-prefix=$PWD=/zos-core03 -C link-arg=--max-memory=4194304" \
    cargo +stable build --offline --locked --release --lib --target wasm32-unknown-unknown
python3 -B depcheck.py
python3 -B test.py "$out"
