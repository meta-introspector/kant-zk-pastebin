#!/usr/bin/env bash
# microflake-build.sh — Build pastebin from bare mirror submodule flakes
#
# Usage: ./microflake-build.sh [step]
#   step: mirrors  — verify/push all submodule commits to bare mirrors
#         generate — generate Cargo.lock + microflake for each submodule crate
#         verify   — nix build each microflake standalone
#         build    — full nix build of pastebin from combined mirrors
#         all      — run all steps (default)

set -euo pipefail
cd "$(dirname "$0")"

STEP="${1:-all}"
echo "=== microflake-build: $STEP ==="

REPO_ROOT="$(pwd)"
MIRROR_BASE="/mnt/data1/git"
GITHUB_MIRROR="$MIRROR_BASE/github.com"
SOLANA_MIRROR="$MIRROR_BASE/solana.solfunmeme.com"

# ── Submodule registry ──────────────────────────────────────────────
# Each entry: repo_name:submodule_path:mirror_path:target_rev:subdirs
SUBMODULES=(
  "html5ever:plugins/html5ever:$SOLANA_MIRROR/html5ever.git:70a1b3a7568f7e302367dd4b2806cf2fd22758cc:."
  "rust-cssparser:plugins/html5ever/cssparser:$SOLANA_MIRROR/rust-cssparser.git:aae89a8330951e441e0010fdd1907be4cb119eb5:."
  "oxc:plugins/oxc:$MIRROR_BASE/nix/time/2024/09/01/oxc:0fa6e540aa11d2026d8fcaacfe8381253ddcafd5:."
  "erdfa-canonical:erdfa-canonical:$SOLANA_MIRROR/erdfa-canonical.git:6645fbbb3450ea142e461517cb170d74126310f1:."
  "zos-circuit-optimizer:plugins/zos-circuit-optimizer:$SOLANA_MIRROR/zos-circuit-optimizer.git:2d26e13f3399438095ae70bec40d81af65f3e014:."
  "zkperf:zkperf:$MIRROR_BASE/../home/mdupont/git/github.com/meta-introspector/zkperf.git:4346b6e28b1ca4a6a51a30f2d386d09dd2638c33:."
  "erdfa-publish:erdfa-canonical/bindings/rust:$SOLANA_MIRROR/erdfa-publish.git:92f0bae8640c6defed0c6d2abc5e136e161c74d4:."
  "rust-ipfs:erdfa-canonical/bindings/rust/vendor/rust-ipfs:$MIRROR_BASE/../home/mdupont/git/github.com/meta-introspector/rust-ipfs.git:928037957a257f6b81d38aa87c74dda99123c2be:."
)

# ── Step 1: Verify and push submodule commits to bare mirrors ───────
step_mirrors() {
  echo "--- Step: mirrors ---"
  for entry in "${SUBMODULES[@]}"; do
    IFS=':' read -r name subpath mirror rev subdirs <<< "$entry"
    echo "  [$name] submodule=$subpath mirror=$mirror rev=$rev"

    if [ ! -d "$mirror" ]; then
      echo "    ERROR: Mirror $mirror does not exist!"
      exit 1
    fi

    if git -C "$mirror" cat-file -t "$rev" &>/dev/null; then
      echo "    ✅ Commit found in mirror"
    else
      echo "    ⏳ Pushing commit from submodule checkout..."
      if [ -d "$subpath" ]; then
        git -C "$subpath" push "$mirror" "$rev:refs/heads/main" 2>&1 | sed 's/^/      /'
        echo "    ✅ Pushed"
      else
        echo "    ⚠️  Submodule checkout missing at $subpath"
      fi
    fi
  done
}

# ── Step 2: Generate microflake Cargo.locks ─────────────────────────
step_generate() {
  echo "--- Step: generate ---"
  FLAKES_DIR="$REPO_ROOT/flakes"
  mkdir -p "$FLAKES_DIR"

  # Generate Cargo.lock for cssparser-macros
  echo "  Generating Cargo.lock for cssparser-macros..."
  TMPDIR=$(mktemp -d)
  git clone --depth=1 "$SOLANA_MIRROR/rust-cssparser.git" "$TMPDIR/cssparser" 2>/dev/null || \
    cp -r "$REPO_ROOT/plugins/html5ever/cssparser" "$TMPDIR/cssparser"
  if [ -f "$TMPDIR/cssparser/macros/Cargo.toml" ]; then
    cd "$TMPDIR/cssparser/macros"
    cargo generate-lockfile 2>&1 | sed 's/^/    /'
    cp Cargo.lock "$FLAKES_DIR/cssparser-macros/"
    echo "    ✅ Cargo.lock generated"
  fi
  rm -rf "$TMPDIR"
}

# ── Step 3: Verify microflakes build ─────────────────────────────────
step_verify() {
  echo "--- Step: verify ---"
  for f in "$REPO_ROOT/flakes"/*/flake.nix; do
    dir="$(dirname "$f")"
    name="$(basename "$dir")"
    echo "  Verifying microflake: $name"
    (cd "$dir" && nix build --no-link 2>&1) | tail -3
    echo "    ✅ $name built"
  done
}

# ── Step 4: Full build ──────────────────────────────────────────────
step_build() {
  echo "--- Step: build ---"
  # Ensure all flake inputs are git-tracked
  git add flake.nix ideacloud.nix apply.nix m1cr0.nix flakes/ 2>/dev/null || true
  echo "  Starting nix build (will take a while on first run)..."
  nix build --no-link "$REPO_ROOT" 2>&1 | tail -10
  echo "    ✅ Build complete"
}

# ── Run selected step ───────────────────────────────────────────────
case "$STEP" in
  mirrors)   step_mirrors ;;
  generate)  step_generate ;;
  verify)    step_verify ;;
  build)     step_build ;;
  all)
    step_mirrors
    step_generate
    step_verify
    step_build
    ;;
  *)
    echo "Unknown step: $STEP"
    echo "Usage: $0 [mirrors|generate|verify|build|all]"
    exit 1
    ;;
esac

echo "=== Done: $STEP ==="
