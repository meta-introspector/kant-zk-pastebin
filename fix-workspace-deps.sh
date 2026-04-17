#!/usr/bin/env bash
# Iteratively find missing workspace.dependencies and add them from oxc's Cargo.toml
set -euo pipefail

OXC_TOML="plugins/oxc/Cargo.toml"
ROOT_TOML="Cargo.toml"
ANCHOR="unicode-id-start"  # insert new deps after this line

for i in $(seq 1 20); do
    missing=$(nix develop --command cargo check 2>&1 \
        | grep "was not found in" \
        | grep -oP '`dependency\.\K[^`]+' \
        | sort -u || true)

    [[ -z "$missing" ]] && echo "✓ All workspace deps resolved after $i iterations" && exit 0

    echo "Iteration $i — missing: $missing"

    for dep in $missing; do
        # Already present? skip
        grep -qP "^${dep}\s*[=\{]" "$ROOT_TOML" && continue

        # Look up in oxc workspace
        val=$(grep -P "^${dep}\s*[=\{]" "$OXC_TOML" | head -1 || true)

        # Fallback: try html5ever workspace
        [[ -z "$val" ]] && val=$(grep -P "^${dep}\s*[=\{]" plugins/html5ever/Cargo.toml | head -1 || true)

        # Last resort: wildcard version
        [[ -z "$val" ]] && val="${dep} = \"*\""

        echo "  + $val"
        sed -i "/^${ANCHOR}/a ${val}" "$ROOT_TOML"
    done
done

echo "✗ Still missing deps after 20 iterations — check manually"
exit 1
