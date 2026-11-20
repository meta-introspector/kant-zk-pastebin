"""Trusted lab coordinator for one synthetic operation."""
import struct
import subprocess
import tempfile
from pathlib import Path


LIMITS = (4096, 64, 32, 1048576, 64)
OPERATION = b"treasury:debit:7"


def frame(*fields):
    return b"".join(struct.pack("<I", len(value)) + value for value in fields)


def authorize(db, adapter, verifier, trusted_key, message, signature, artifact,
              operation, principal):
    # The principal comes from trusted host context. This fixture has no login layer.
    if principal != "treasury":
        return "DENIED_AUTHORITY"
    if operation != OPERATION:
        return "DENIED_OPERATION"
    fields = (message, signature, trusted_key, artifact, operation)
    if any(len(value) > limit for value, limit in zip(fields, LIMITS)):
        return "DENIED_LIMIT"
    try:
        result = subprocess.run(verifier, input=frame(*fields), capture_output=True,
                                timeout=5, check=False)
    except (OSError, subprocess.TimeoutExpired):
        return "DENIED_VERIFICATION"
    if result.returncode != 0 or result.stdout != b"1\n":
        return "DENIED_VERIFICATION"

    # Only the trusted adapter can write. It authenticates and binds these exact
    # bytes again using its independently pinned key and owns the transaction.
    with tempfile.TemporaryDirectory(dir=db.parent) as scratch:
        paths = [Path(scratch) / name for name in ("message", "signature", "artifact")]
        for path, value in zip(paths, (message, signature, artifact)):
            path.write_bytes(value)
        result = subprocess.run([adapter, "consume", db, *paths, principal,
                                 operation.decode("ascii")], capture_output=True)
        if result.returncode == 0 and result.stdout in (b"APPLIED\n", b"REPLAY\n"):
            return result.stdout.decode("ascii").strip()
        return "DENIED_ADAPTER"
