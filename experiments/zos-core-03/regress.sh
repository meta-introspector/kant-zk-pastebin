#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
out="$(realpath -m "${1:?fresh output path required}")"
repo="$(realpath "${2:?local repository with the published CORE-02 PR head required}")"
object=502827ec3db0186b681008f419a7942fd524dce8:experiments/zos-core-02
test "$(git -C "$repo" rev-parse --verify "$object")" = 37d71100d020f13415dd1c42fd09054d14d1b4fa
mkdir "$out"
git -C "$repo" archive "$object" | tar -x -C "$out"
cd "$out"
sha256sum -c MANIFEST.sha256
"${CORE_LEAN:?absolute pinned Lean path required}" --version
"${CORE_RUSTC:?absolute pinned Rust path required}" -Vv
sha256sum "$CORE_LEAN" "$CORE_RUSTC"
/usr/bin/python3 -B test.py
