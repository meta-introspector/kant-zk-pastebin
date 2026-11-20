"""Rebuild test vectors and audit the executable contract inside an isolated lab."""
import hashlib
import os
from pathlib import Path
import sqlite3
import struct
import subprocess
import sys

from host import LIMITS, OPERATION, authorize, frame

ROOT = Path(__file__).resolve().parent
OUT = Path(sys.argv[1]).resolve()
CORE02 = ROOT / "inputs/core02"
OPENSSL = "/usr/bin/openssl"
ARTIFACT = (ROOT / "inputs/Good.olean").read_bytes()
WASM = OUT / "target/wasm32-unknown-unknown/release/zos_core03.wasm"
NATIVE = [OUT / "target/release/native"]
GUEST = ["node", ROOT / "wasm.mjs", WASM]
CAPACITY = 20 + sum(LIMITS)


def run(args, data=None, *, cwd=OUT, env=None):
    return subprocess.run(args, input=data, cwd=cwd, env=env, check=True,
                          capture_output=True, timeout=20).stdout


def digest(data):
    return hashlib.sha256(data).hexdigest()


assert sys.flags.optimize == 0, "assertions required"
assert digest(ARTIFACT) == "56a7ed934806d8f6e33bd3d938a325761e741dbe534f6e295dc9901d8296a52b"
run(["sha256sum", "-c", ROOT / "inputs/core02.sha256"], cwd=CORE02)
print("PASS pinned CORE02 adapter and fixture checksums")

def git_hash(kind, data):
    return hashlib.sha1(f"{kind} {len(data)}\0".encode() + data).digest()


fixture_blobs = {
    "Check.lean": "bf5e73dca90f5b5cd482fb8b2ed6d48126428a94",
    "Good.lean": "9aa042dce961b30a6fbdb71b3410045fb375ec74",
    "Ref.lean": "eb659a53617c405fdd4968990c3f551e80fc17d6",
    "SorryCase.lean": "be062cbe78c3dbc5d6235e3af3c0a3f86c4d95f0",
    "Mismatch.lean": "1c53cd723947311a0128a99d29c2dae3e525dc13",
}
for name, identity in fixture_blobs.items():
    assert git_hash("blob", (CORE02 / "core01/intake/fixtures" / name).read_bytes()).hex() == identity
print("PASS five pinned JobVerifier Git blobs")

descriptor = (ROOT / "inputs/descriptor.txt").read_bytes()
assert descriptor == (CORE02 / "core01/evidence/descriptor.txt").read_bytes()
message = (CORE02 / "core01/evidence/message.bin").read_bytes()
assert message == (b"zos.core01b.receipt.v1\nverdict=accepted\n"
                   b"basis=source-compiled-jobverifier-fixture\n" + descriptor)

# Deterministic public lab identities. The seed material is deliberately public.
def identity(label):
    key = OUT / f"{label}.der"
    seed = hashlib.sha256(("public-zos-core03-fixture-" + label).encode()).digest()
    key.write_bytes(bytes.fromhex("302e020100300506032b657004220420") + seed)
    args = [OPENSSL, "pkey", "-inform", "DER", "-in", key, "-pubout"]
    spki = run([*args, "-outform", "DER"])
    assert spki[:12] == bytes.fromhex("302a300506032b6570032100") and len(spki) == 44
    return key, spki[12:]


key_file, key = identity("trusted")
_, other_key = identity("other")


def sign(data):
    path = OUT / "to-sign"
    path.write_bytes(data)
    return run([OPENSSL, "pkeyutl", "-sign", "-rawin", "-keyform", "DER",
                "-inkey", key_file, "-in", path])


historical = CORE02 / "core01/evidence"
historical_spki = run([OPENSSL, "pkey", "-pubin", "-in",
                       historical / "trusted-public.pem", "-outform", "DER"])
assert len(historical_spki) == 44 and historical_spki[:12] == bytes.fromhex("302a300506032b6570032100")
historical_sig = (historical / "signature.bin").read_bytes()
historical_bad_sig = bytes([historical_sig[0] ^ 1]) + historical_sig[1:]
historical_pem = (historical / "trusted-public.pem").read_bytes()

signature = sign(message)
bad_signature = bytes([signature[0] ^ 1]) + signature[1:]
valid = frame(message, signature, key, ARTIFACT, OPERATION)


def payload(msg=message, sig=signature, pubkey=key, artifact=ARTIFACT, operation=OPERATION):
    return frame(msg, sig, pubkey, artifact, operation)


def signed(msg):
    return payload(msg=msg, sig=sign(msg))


cases = [
    ("accepted", valid, 1),
    ("archived-lean-issuer-receipt", frame(message, historical_sig, historical_spki[12:],
                                         ARTIFACT, OPERATION), 1),
    ("invalid-signature", payload(sig=bad_signature), 4),
    ("wrong-key", payload(pubkey=other_key), 4),
    ("tampered-descriptor", signed(message.replace(b"proposition=True", b"proposition=False")), 5),
    ("artifact-mismatch", payload(artifact=ARTIFACT + b"bad"), 6),
    ("operation-substitution", payload(operation=b"treasury:debit:8"), 7),
    ("signed-operation-substitution", signed(message.replace(OPERATION, b"treasury:debit:8")), 5),
    ("unauthorized-operation", payload(operation=b"mint:1"), 7),
    ("missing-fields", b"", 2),
    ("truncated-length", valid[:3], 2),
    ("truncated-value", valid[:-1], 2),
    ("truncated-signature", payload(sig=signature[:-1]), 2),
    ("truncated-key", payload(pubkey=key[:-1]), 2),
    ("trailing-frame-byte", valid + b"\0", 2),
    ("signed-duplicate-field", signed(message + b"request=fixture-request-0001\n"), 5),
    ("signed-crlf", signed(message.replace(b"\n", b"\r\n")), 5),
    ("signed-invalid-utf8", signed(message + b"\xff"), 5),
    ("signed-unknown-verdict", signed(message.replace(b"verdict=accepted", b"verdict=unknown")), 5),
    ("oversized-length", struct.pack("<I", 0xffffffff), 3),
    ("oversized-message", payload(msg=b"x" * 4097), 3),
    ("oversized-artifact", payload(artifact=b"x" * 1048577), 3),
    ("artifact-at-limit", payload(artifact=b"x" * 1048576), 6),
    ("oversized-frame", b"x" * (CAPACITY + 1), 3),
]

for name, data, expected in cases:
    expected_bytes = f"{expected}\n".encode()
    assert run(NATIVE, data) == expected_bytes, ("native", name)
    assert run(GUEST, data) == expected_bytes, ("wasm", name)
    print(f"PASS shared {name} {expected} {digest(data)}")

assert run([*GUEST, "--audit-abi"]) == b"3\n"
print("PASS WASM direct overlength ABI call and memory growth cap, import-free")
broken = OUT / "broken.wasm"
broken.write_bytes(b"invalid module")
assert run(["node", ROOT / "wasm.mjs", broken], valid) == b"8\n"
print("PASS WASM loader failure maps to indeterminate")

adapter = OUT / "adapter"
trusted_pem = OUT / "trusted.pem"
trusted_pem.write_bytes(historical_pem)
run(["rustc", "+stable", "--edition=2021", "-Dwarnings", CORE02 / "src/main.rs",
     "-o", adapter], env={**os.environ, "CORE02_TRUSTED_KEY": str(trusted_pem)})
db = OUT / "synthetic.db"
control_db = OUT / "untouched.db"
run([adapter, "init", db])
run([adapter, "init", control_db])
control_hash = digest(control_db.read_bytes())


def snapshot(expected):
    with sqlite3.connect(f"{db.as_uri()}?mode=ro", uri=True) as conn:
        receipts = conn.execute("SELECT * FROM receipts").fetchall()
        effects = conn.execute("SELECT * FROM effects").fetchall()
        balance = conn.execute("SELECT balance FROM treasury").fetchall()
        assert conn.execute("PRAGMA integrity_check").fetchall() == [("ok",)]
        assert conn.execute("PRAGMA foreign_key_check").fetchall() == []
        domain, request = "zos.core01b.synthetic.v1", "fixture-request-0001"
        expected_receipt = (domain, request, message.decode(), historical_sig.hex(), digest(ARTIFACT),
                            OPERATION.decode(), digest(historical_pem), "treasury")
        assert receipts == ([expected_receipt] if expected else [])
        assert effects == ([(domain, request, -7)] if expected else [])
        assert balance == [(93 if expected else 100,)]


def call(verifier=GUEST, principal="treasury", operation=OPERATION, sig=historical_sig):
    return authorize(db, adapter, verifier, historical_spki[12:], message, sig, ARTIFACT,
                     operation, principal)


def simulated_output(status):
    return [sys.executable, "-c", f"print({status})"]


tests = [
    ("unknown guest status", "DENIED_VERIFICATION", {"verifier": simulated_output(999)}),
    ("indeterminate guest", "DENIED_VERIFICATION",
     {"verifier": ["node", ROOT / "wasm.mjs", broken]}),
    ("unavailable verifier", "DENIED_VERIFICATION", {"verifier": [OUT / "missing"]}),
    ("timed out verifier", "DENIED_VERIFICATION",
     {"verifier": [sys.executable, "-c", "import time; time.sleep(10)"]}),
    ("unauthorized principal", "DENIED_AUTHORITY", {"principal": "foreign-dao"}),
    ("unauthorized operation", "DENIED_OPERATION", {"operation": b"mint:1"}),
    ("bad signature", "DENIED_VERIFICATION", {"sig": historical_bad_sig}),
    ("forged authentication result", "DENIED_ADAPTER",
     {"verifier": simulated_output(1), "sig": historical_bad_sig}),
]
for name, outcome, kwargs in tests:
    assert call(**kwargs) == outcome, name
    snapshot(False)
    print(f"PASS host {name} {outcome}, no mutation")

assert call() == "APPLIED"
snapshot(True)
assert call() == "REPLAY"
snapshot(True)
assert call(verifier=NATIVE) == "REPLAY"
snapshot(True)
print("PASS host archived Lean receipt through WASM-to-SQLite authorized apply, transactional receipt, replay with no second effect")
assert digest(control_db.read_bytes()) == control_hash
print("PASS separate SQLite database remains byte-identical")
print("SQLite", sqlite3.sqlite_version)
for binary in [NATIVE[0], WASM]:
    print("SHA256", binary.name, digest(binary.read_bytes()))
