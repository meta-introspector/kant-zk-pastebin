#!/usr/bin/env bash
# scan.sh — Scan repo for files matching idea cloud fingerprints
#
# Outputs JSON array of { path, content } to stdout.
# Reads a list of file patterns from a scan.config file or uses defaults.

set -euo pipefail

REPO_ROOT="${1:-$(pwd)}"
cd "$REPO_ROOT"

# Default scan targets: files we know contain structured metadata
SCAN_TARGETS=(
  ".gitmodules"
  "Cargo.toml"
  "flake.nix"
  "plugins/html5ever/.gitmodules"
  "plugins/html5ever/Cargo.toml"
  "plugins/html5ever/flake.nix"
  "plugins/oxc/Cargo.toml"
  "plugins/oxc/flake.nix"
  "plugins/zos-circuit-optimizer/Cargo.toml"
  "plugins/zos-circuit-optimizer/flake.nix"
  "erdfa-canonical/Cargo.toml"
  "erdfa-canonical/flake.nix"
  "erdfa-canonical/bindings/rust/Cargo.toml"
  "erdfa-canonical/bindings/rust/flake.nix"
  "erdfa-clean/Cargo.toml"
  "erdfa-clean/flake.nix"
  "zkperf/Cargo.toml"
  "zkperf/flake.nix"
  "erdfa-publish/Cargo.toml"
  "erdfa-publish/flake.nix"
)

echo "["
first=true
for target in "${SCAN_TARGETS[@]}"; do
  if [ -f "$target" ]; then
    if [ "$first" = true ]; then
      first=false
    else
      echo ","
    fi
    # Escape content for JSON
    content=$(sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g; s/\r//g' "$target" | tr '\n' '\\n')
    echo '  { "path": "'"$target"'", "content": "'"$content"'" }'
  fi
done
echo "]"
