"""Run from a clean package with CORE_LEAN and CORE_RUSTC set."""
import hashlib
import os
from pathlib import Path
import selectors
import shutil
import signal
import sqlite3
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent
WORK = Path(tempfile.mkdtemp(prefix="run-", dir=ROOT))
os.environ["TMPDIR"] = str(WORK)
os.environ["LC_ALL"] = "C"
BASE = WORK / "core01"
shutil.copytree(ROOT / "core01", BASE)
RUN = subprocess.run

def command(argv, *, cwd=WORK, code=0, env=None):
    out = RUN([str(arg) for arg in argv], cwd=cwd, env=env, capture_output=True, text=True, timeout=240)
    assert out.returncode == code, (out.returncode, out.stdout, out.stderr)
    return out

def digest(data):
    return hashlib.sha256(data).hexdigest()

command(["sha256sum", "-c", "PUBLIC_MANIFEST.sha256"], cwd=BASE)
baseline = command(["/usr/bin/python3", "-B", "rebuild/isolate.py"], cwd=BASE)
print(baseline.stdout.splitlines()[0])
bundle, = (BASE / "rebuild").glob("evidence-*")
print(command(["/usr/bin/python3", "-B", "rebuild/verify.py", bundle], cwd=BASE).stdout, end="")
command(["sha256sum", "-c", "../../evidence/matched-core01c.sha256"], cwd=bundle)
print("PASS CORE01 artifact, descriptor and message match archived digests")
for line in (bundle / "tests.stdout.log").read_text().splitlines():
    if line.startswith(("VERIFIER", "COMPILER", "PASS 02", "PASS 03", "PASS 10")):
        print(line)
rust = Path(os.environ["CORE_RUSTC"]).resolve(strict=True)
print("SQLite", sqlite3.sqlite_version, "OpenSSL", command(["/usr/bin/openssl", "version"]).stdout.strip())

def compile_adapter(name, key, hooks=False):
    args = [rust, "--edition=2021", "-Dwarnings"]
    if hooks:
        args += ["--cfg", "core02_test"]
    command([*args, ROOT / "src/main.rs", "-o", name],
            env={**os.environ, "CORE02_TRUSTED_KEY": str(key)})
    return WORK / name

key = bundle / "trusted-public.pem"
adapter = compile_adapter("adapter", key)
hooks = compile_adapter("adapter-test", key, True)
wrong_key = compile_adapter("wrong-key", bundle / "other-public.pem")
print(command(["ldd", adapter]).stdout.replace(str(WORK), "<run>"), end="")
msg, sig, artifact = [bundle / n for n in ("message.bin", "signature.bin", "Good.olean")]
authority, operation = "treasury", "treasury:debit:7"
request = [msg, sig, artifact, authority, operation]

def newdb(name):
    path = WORK / f"{name}.db"
    command([adapter, "init", path])
    return path

def call(db, inputs=request, *, exe=adapter, mode=None):
    action = ["consume", db] if mode is None else ["test", db, mode]
    return [str(p) for p in [exe, *action, *inputs]]

def snapshot(db, expected):
    with sqlite3.connect(db) as conn:
        assert conn.execute("PRAGMA integrity_check").fetchall() == [("ok",)]
        assert conn.execute("PRAGMA foreign_key_check").fetchall() == []
        rows = conn.execute("SELECT * FROM receipts").fetchall()
        effects = conn.execute("SELECT * FROM effects").fetchall()
        balance, = conn.execute("SELECT balance FROM treasury").fetchone()
        if expected:
            domain, rid = "zos.core01b.synthetic.v1", "fixture-request-0001"
            assert rows == [(domain, rid, msg.read_text(), sig.read_bytes().hex(), digest(artifact.read_bytes()),
                             operation, digest(key.read_bytes()), authority)]
            assert effects == [(domain, rid, -7)]
            assert balance == 93
        else:
            assert rows == effects == [] and balance == 100
        return rows, effects, balance

def rejected(label, db, error, *args, expected=False, **kwargs):
    before = snapshot(db, expected)
    result = command(call(db, *args, **kwargs), code=1)
    assert result.stdout == "" and result.stderr.startswith(f"DENIED {error}"), result.stderr
    assert snapshot(db, expected) == before
    print(f"PASS {label} {error} committed state unchanged")

db = newdb("main")
tampered = WORK / "bad-signature"
tampered.write_bytes(bytes([sig.read_bytes()[0] ^ 1]) + sig.read_bytes()[1:])
rejected("invalid signature", db, "SIGNATURE", [msg, tampered, *request[2:]])
rejected("wrong trusted key", db, "SIGNATURE", exe=wrong_key)
bad_artifact = WORK / "bad-artifact"
bad_artifact.write_bytes(artifact.read_bytes() + b"tampered")
rejected("modified artifact", db, "ARTIFACT", [msg, sig, bad_artifact, authority, operation])
rejected("operation substitution", db, "OPERATION", [*request[:4], "treasury:debit:8"])
rejected("unauthorized DAO identity", db, "AUTHORITY", [*request[:3], "foreign-dao", operation])
short = WORK / "short-signature"
short.write_bytes(b"")
rejected("malformed envelope", db, "SIGNATURE", [msg, short, *request[2:]])
rejected("SQLite write failure", db, "STEP:8:", exe=hooks, mode="write-failure")
rejected("rollback after receipt insert", db, "INJECTED_ROLLBACK", exe=hooks, mode="rollback")
with sqlite3.connect(db) as blocker:
    blocker.execute("BEGIN IMMEDIATE")
    rejected("busy competing writer", db, "EXEC:5:database is locked")
    blocker.rollback()

# Sign altered messages with a separately pinned test-only identity to reach
# the policy checks even when signature authentication succeeds.
with tempfile.TemporaryDirectory(dir=WORK) as signing:
    signing = Path(signing)
    command(["/usr/bin/openssl", "genpkey", "-algorithm", "ED25519", "-out", signing / "key.pem"])
    altered_key = WORK / "test-public.pem"
    command(["/usr/bin/openssl", "pkey", "-in", signing / "key.pem", "-pubout", "-out", altered_key])
    test_signer_adapter = compile_adapter("test-signer-adapter", altered_key)
    for label, data in (
        ("signed descriptor substitution", msg.read_bytes().replace(b"proposition=True", b"proposition=False")),
        ("signed operation substitution", msg.read_bytes().replace(b"treasury:debit:7", b"treasury:debit:8")),
        ("signed duplicate request field", msg.read_bytes() + b"request=fixture-request-0001\n"),
        ("signed unknown request", msg.read_bytes().replace(b"request-0001", b"request-0002")),
        ("signed forged accepted basis", msg.read_bytes().replace(b"source-compiled-jobverifier-fixture", b"client-asserted")),
    ):
        altered_msg, altered_sig = WORK / "altered-message", WORK / "altered-sig"
        altered_msg.write_bytes(data)
        command(["/usr/bin/openssl", "pkeyutl", "-sign", "-rawin", "-inkey", signing / "key.pem",
                 "-in", altered_msg, "-out", altered_sig])
        rejected(label, db, "DESCRIPTOR", [altered_msg, altered_sig, *request[2:]], exe=test_signer_adapter)

for label in ("invalid", "sorry", "indeterminate"):
    # The isolated CORE-01 executable ran each failure at the real verifier gate.
    # Test that its failed unsigned assertion cannot mutate the persistent consumer.
    logs = (bundle / "tests.stdout.log").read_text()
    assert any(x.endswith(f"-{label} complete_state_unchanged=true") for x in logs.splitlines())
    rejected(f"Lean {label}: no authenticated receipt", db, "SIGNATURE", [msg, short, *request[2:]])

assert command(call(db, exe=hooks, mode="same-process")).stdout == "APPLIED\nREPLAY\n"
snapshot(db, True)
assert command(call(db)).stdout == "REPLAY\n"
snapshot(db, True)
print("PASS valid receipt, same-process replay and restart replay")
race = newdb("race")
peers = [subprocess.Popen(call(race), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) for _ in range(12)]
verdicts = []
for peer in peers:
    out, err = peer.communicate(timeout=10)
    assert peer.returncode == 0 and not err, (peer.returncode, err)
    verdicts.append(out.strip())
assert verdicts.count("APPLIED") == 1 and verdicts.count("REPLAY") == 11
snapshot(race, True)
print("PASS 12 independent processes: one APPLIED, eleven REPLAY")

for trial in range(2):
    for phase in ("before-commit", "after-commit"):
        crash = newdb(f"crash-{trial}-{phase}")
        with subprocess.Popen(call(crash, exe=hooks, mode=phase), stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, text=True) as victim:
            try:
                with selectors.DefaultSelector() as selector:
                    selector.register(victim.stdout, selectors.EVENT_READ)
                    assert selector.select(timeout=10), phase
                    assert victim.stdout.readline() == f"CHECKPOINT {phase}\n"
                victim.send_signal(signal.SIGKILL)
                out, err = victim.communicate(timeout=10)
                assert victim.returncode == -signal.SIGKILL and not out and not err
            finally:
                if victim.poll() is None:
                    victim.kill()
        committed = phase == "after-commit"
        snapshot(crash, committed)
        assert command(call(crash)).stdout == ("REPLAY\n" if committed else "APPLIED\n")
        assert command(call(crash)).stdout == "REPLAY\n"
        snapshot(crash, True)
        print(f"PASS actual SIGKILL {trial + 1} {phase}: committed_at_reopen={committed}, retry and replay verified")

incompatible = newdb("incompatible")
with sqlite3.connect(incompatible) as conn:
    conn.execute("PRAGMA user_version=99")
rejected("incompatible schema version", incompatible, "SCHEMA")
with sqlite3.connect(incompatible) as conn:
    assert conn.execute("PRAGMA user_version").fetchone() == (99,)
changed = newdb("changed")
with sqlite3.connect(changed) as conn:
    conn.execute("CREATE TRIGGER reject BEFORE INSERT ON effects BEGIN SELECT raise(ABORT,'modified'); END")
rejected("unexpected schema trigger", changed, "SCHEMA")
corrupt = WORK / "corrupt.db"
corrupt.write_bytes(b"invalid database bytes" * 50)
before = corrupt.read_bytes()
result = command(call(corrupt), code=1)
assert ":26:" in result.stderr and corrupt.read_bytes() == before
assert not Path(str(corrupt) + "-journal").exists()
print("PASS corrupt DB SQLITE_NOTADB, original bytes preserved")

with sqlite3.connect(db) as conn:
    conn.execute("PRAGMA foreign_keys=ON")
    valid = snapshot(db, True)[0][0]
    for table in ("receipts", "effects"):
        try:
            conn.execute(f"DELETE FROM {table}")
            conn.commit()
        except sqlite3.IntegrityError:
            conn.rollback()
        else:
            raise AssertionError(f"one-sided removal committed: {table}")
    try:
        conn.execute("INSERT INTO receipts VALUES (?,?,?,?,?,?,?,?)",
                     (*valid[:2], "distinct audit payload", *valid[3:]))
    except sqlite3.IntegrityError as error:
        assert error.sqlite_errorname == "SQLITE_CONSTRAINT_PRIMARYKEY", error
        conn.rollback()
    else:
        raise AssertionError("duplicate request insert succeeded")
snapshot(db, True)
print("PASS independent SQLite deferred foreign keys and duplicate request constraint")
print("PASS all CORE02 mandatory executable scenarios")
shutil.rmtree(WORK)
