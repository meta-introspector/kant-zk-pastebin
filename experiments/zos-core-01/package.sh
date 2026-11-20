#!/bin/bash
set -euo pipefail
export LC_ALL=C
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
cd -- "$root"
sha256sum -c PUBLIC_MANIFEST.sha256 >&2
{
    printf '%s\0' ./PUBLIC_MANIFEST.sha256
    sed -E 's/^[[:xdigit:]]{64}  //' PUBLIC_MANIFEST.sha256 | tr '\n' '\0'
} | sort -z | tar --null --no-recursion --files-from=- --format=ustar --mtime=@0 \
    --owner=0 --group=0 --numeric-owner --mode='u=rw,go=r' -cf - | gzip -n -9
