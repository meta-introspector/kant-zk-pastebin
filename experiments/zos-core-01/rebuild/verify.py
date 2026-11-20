"""Verify the exported synthetic receipt and matrix without running the adapter."""
import hashlib
from pathlib import Path
import re
import subprocess
import sys

directory = Path(sys.argv[1]).resolve(strict=True)
descriptor = (directory / "descriptor.txt").read_bytes()
header = (b"zos.core01b.receipt.v1\nverdict=accepted\n"
          b"basis=source-compiled-jobverifier-fixture\n")
if (directory / "message.bin").read_bytes() != header + descriptor:
    raise SystemExit("Signed payload differs from the exported descriptor")
if (directory / "signature.bin").stat().st_size != 64:
    raise SystemExit("Unexpected Ed25519 signature length")
fields = dict(line.split(b"=", 1) for line in descriptor.splitlines()[1:])
for field, filename in {
    b"checker": "Check.lean", b"source": "Good.lean",
    b"reference-source": "Ref.lean", b"artifact": "Good.olean",
    b"reference-artifact": "Ref.olean",
}.items():
    actual = hashlib.sha256((directory / filename).read_bytes()).hexdigest().encode()
    if fields[field + b"-sha256"] != actual:
        raise SystemExit(f"Receipt digest mismatch: {filename}")
    print(f"PASS signed digest for {filename}")
for key, expected in (("trusted-public.pem", 0), ("other-public.pem", 1)):
    argv = ["/usr/bin/openssl", "pkeyutl", "-rawin", "-verify", "-pubin",
            "-inkey", key, "-in", "message.bin", "-sigfile", "signature.bin"]
    result = subprocess.run(argv, cwd=directory, capture_output=True,
                            env={"LC_ALL": "C", "PATH": "/usr/bin:/bin"})
    print(*argv)
    print(f"exit={result.returncode} stdout={result.stdout!r} stderr={result.stderr!r}")
    expected_message = (b"Signature Verified Successfully" if expected == 0
                        else b"Signature Verification Failure")
    if result.returncode != expected or expected_message not in result.stdout or (expected == 0 and result.stderr):
        raise SystemExit(f"Unexpected authentication outcome: {key}")
lines = (directory / "tests.stdout.log").read_text().splitlines()
passes = [line for line in lines if line.startswith("PASS ")]
positive = [line for line in passes if line == "PASS 01-valid"]
negative = [line for line in passes if re.fullmatch(r"PASS (0[2-9]|1[0-5])-[a-z-]+ complete_state_unchanged=true", line)]
if len(passes) != 15 or len(positive) != 1 or sorted(int(line[5:7]) for line in negative) != list(range(2, 16)):
    raise SystemExit("Unexpected matrix counts")
if (directory / "tests.stderr.log").stat().st_size:
    raise SystemExit("Matrix stderr is nonempty")
print("PASS 15/15 matrix cases, 14/14 complete state assertions, 0 skipped")
