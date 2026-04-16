#!/usr/bin/env bash
# Document, commit to new branch, and push to local bare mirror for each dirty repo
set -e

BRANCH="feature/plugin-spinoff-snapshot-$(date +%Y%m%d-%H%M%S)"

echo "Branch name: $BRANCH"
echo ""

# ── 1. rust-ipfs (innermost) ──────────────────────────────────────────────────
echo "=== [1/4] erdfa-canonical/bindings/rust/vendor/rust-ipfs ==="
IPFS_DIR="erdfa-canonical/bindings/rust/vendor/rust-ipfs"
git -C "$IPFS_DIR" checkout -b "$BRANCH"
cat > "$IPFS_DIR/CHANGES.md" <<'EOF'
# Unstaged Changes

## vendor/rust-ipfs submodule pointer bump

- Updated submodule pointer from `928037957` to `ad0b88c70`
- This tracks a newer commit on the rust-ipfs vendored dependency
EOF
git -C "$IPFS_DIR" add CHANGES.md
git -C "$IPFS_DIR" commit -m "docs: document submodule pointer bump to ad0b88c70"
git -C "$IPFS_DIR" push local-bare "$BRANCH"
echo "  ✓ pushed to local-bare"

# ── 2. bindings/rust ─────────────────────────────────────────────────────────
echo ""
echo "=== [2/4] erdfa-canonical/bindings/rust ==="
RUST_DIR="erdfa-canonical/bindings/rust"
git -C "$RUST_DIR" checkout -b "$BRANCH"
cat > "$RUST_DIR/CHANGES.md" <<'EOF'
# Unstaged Changes

## vendor/rust-ipfs submodule updated

- `vendor/rust-ipfs` bumped from `928037957` → `ad0b88c70` (v0.11.18-432)
- See vendor/rust-ipfs/CHANGES.md for details
EOF
git -C "$RUST_DIR" add vendor/rust-ipfs CHANGES.md
git -C "$RUST_DIR" commit -m "docs: bump vendor/rust-ipfs to ad0b88c70 (v0.11.18-432)"
git -C "$RUST_DIR" push bare "$BRANCH"
echo "  ✓ pushed to bare"

# ── 3. erdfa-canonical ────────────────────────────────────────────────────────
echo ""
echo "=== [3/4] erdfa-canonical ==="
CANONICAL_DIR="erdfa-canonical"
git -C "$CANONICAL_DIR" checkout -b "$BRANCH"
cat > "$CANONICAL_DIR/CHANGES.md" <<'EOF'
# Unstaged Changes

## bindings/rust submodule updated

- `bindings/rust` submodule pointer updated (dirty → committed)
- Tracks rust-ipfs vendor bump to v0.11.18-432
EOF
git -C "$CANONICAL_DIR" add bindings/rust CHANGES.md
git -C "$CANONICAL_DIR" commit -m "docs: update bindings/rust submodule pointer"
git -C "$CANONICAL_DIR" push origin "$BRANCH"
echo "  ✓ pushed to origin (solana.solfunmeme.com bare)"

# ── 4. pastebin root ──────────────────────────────────────────────────────────
echo ""
echo "=== [4/4] pastebin root ==="
git checkout -b "$BRANCH"
cat > CHANGES.md <<EOF
# Unstaged Changes — $(date -u +%Y-%m-%dT%H:%M:%SZ)

## flake.nix / flake.lock

- zkperf input URL changed from local working tree to bare mirror:
  \`file:///mnt/data1/kant/pastebin/zkperf\` → \`file:///mnt/data1/git/github.com/meta-introspector/zkperf.git\`
- zkperf ref changed from pinned commit hash to named branch \`feat/rebase-all\`
- flake.lock updated accordingly (narHash, revCount, lastModified)

## New source files (src/bin/)

### js_interpreter.rs
- OXC-based JS interpreter with execution tracing
- Evaluates variable declarations, literals, call expressions
- Records execution steps with orbifold coordinates (erdfa_dasl)

### js_parser.rs
- CLI tool: parses a JS file via OXC and reports statement count
- Exits non-zero on parse errors

### test_generator.rs
- Generates 194 test cases from Monster group irrep symmetries
- Uses Monster primes to derive orbifold coords per irrep
- Outputs AFL++ seed corpus to \`fuzz/corpus/\`

## Submodule updates

- \`erdfa-canonical\`: bindings/rust vendor bump (rust-ipfs v0.11.18-432)
EOF
git add flake.nix flake.lock src/bin/js_interpreter.rs src/bin/js_parser.rs src/bin/test_generator.rs erdfa-canonical CHANGES.md git-status-recursive.sh commit-and-push.sh
git commit -m "docs: document flake zkperf URL change, new JS bins, submodule bumps"
git push bare "$BRANCH"
echo "  ✓ pushed to bare (meta-introspector/kant-zk-pastebin)"

echo ""
echo "All done. Branch: $BRANCH"
