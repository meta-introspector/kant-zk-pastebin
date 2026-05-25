#!/usr/bin/env bash
# generate-microflakes.sh — Run scan + apply ideacloud, emit microflakes
#
# Usage: ./generate-microflakes.sh [repo-root]
#
# Output:
#   generated-flakes/<idea-id>/<artifact-name>/flake.nix

set -euo pipefail

REPO_ROOT="${1:-$(pwd)}"
cd "$REPO_ROOT"

GENERATED_DIR="generated-flakes"
mkdir -p "$GENERATED_DIR"

echo "=== Scanning repo ==="
SCAN_OUTPUT=$(./scan.sh "$REPO_ROOT" 2>/dev/null)

echo "=== Applying ideacloud ==="
# For now, parse scan output with jq if available, otherwise use bash
if command -v jq &>/dev/null; then
  echo "$SCAN_OUTPUT" | jq -c '.[]' | while read -r file; do
    path=$(echo "$file" | jq -r '.path')
    content=$(echo "$file" | jq -r '.content')

    # Check against each idea pattern
    for idea_dir in "$REPO_ROOT/ideacloud.nix"; do
      # Determine submodule path from .gitmodules
      if echo "$path" | grep -q '\.gitmodules'; then
        paths=$(echo "$content" | grep 'path = ' | sed 's/.*path = //' | tr -d '"')
        for sub_path in $paths; do
          mkdir -p "$GENERATED_DIR/git.submodule/$sub_path"
          cat > "$GENERATED_DIR/git.submodule/$sub_path/flake.nix" << FLAKEEOF
{
  description = "microflake: git submodule $sub_path";
  outputs = { self }: {
    packages.x86_64-linux.default = builtins.path {
      path = ./${sub_path};
      name = "${sub_path}";
    };
  };
}
FLAKEEOF
        done
      fi
    done
  done
  echo "=== Generated microflakes in $GENERATED_DIR/ ==="
  find "$GENERATED_DIR" -name "flake.nix" | sort
else
  echo "jq not found — installing..."
  nix-shell -p jq --run "echo 'jq available'; $0 '$REPO_ROOT'"
fi
