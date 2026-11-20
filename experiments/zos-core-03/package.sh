#!/bin/bash
set -euo pipefail
root="$(realpath "$(dirname "$0")")"
archive="$(realpath -m "${1:?archive path outside the handoff required}")"
if [[ "$archive" == "$root" || "$archive" == "$root/"* || -e "$archive" ]]; then
    echo "Provide a new archive path outside the handoff" >&2
    exit 1
fi
cd "$root"
export LC_ALL=C
sha256sum -c MANIFEST.sha256 >&2
tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
    --mode='a=rX,u+w' --format=gnu -cf - . | gzip -n >"$archive"
sha256sum "$archive"
