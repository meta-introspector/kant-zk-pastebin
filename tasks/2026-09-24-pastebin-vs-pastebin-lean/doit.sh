#!/usr/bin/env bash
# Run the Rust ↔ Lean pastebin comparison. See SYSTEM.md.
set -euo pipefail
exec bash /mnt/data1/kant/pastebin/scripts/compare-pastebin-lean.sh "$@"
