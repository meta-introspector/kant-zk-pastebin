import hashlib
import hmac
import json
import os
from pathlib import Path
import secrets
import sqlite3
import subprocess
import sys

root=Path(os.environ["P11J_LAB"])
rust=Path(os.environ["P11J_RUST"])
python=Path(os.environ["P11J_PYTHON"])

identity=secrets.token_hex(16)
tag="ab"*32
other="cd"*32
key=secrets.token_bytes(32)

environments={}
observations=[]
differences=[]
checks={}

def check(name,ok):
    ok=bool(ok)
    checks[name]=ok
    print(f"CHECK={name} PASS={ok}",flush=True)
    if not ok:
        raise AssertionError(name)

def receipt(rid,value=tag):
    data=b"ZOS-AUTH-COMMIT-V1\x00"
    for field in (identity,rid,value):
        encoded=field.encode("ascii")
        data+=len(encoded).to_bytes(4,"big")+encoded
    return hmac.new(key,data,hashlib.sha256).hexdigest()

for implementation in ("python","rust"):
    folder=root/implementation
    folder.mkdir()

    database=folder/"canonical.sqlite"
    keyfile=folder/"authority.key"
    keyfile.write_bytes(key)
    keyfile.chmod(0o600)

    with sqlite3.connect(database) as con:
        con.execute("PRAGMA journal_mode=DELETE")
        con.execute("PRAGMA synchronous=FULL")
        con.execute(
            "CREATE TABLE claims("
            "dbid TEXT NOT NULL,"
            "rid TEXT NOT NULL,"
            "tag TEXT NOT NULL,"
            "state TEXT NOT NULL,"
            "PRIMARY KEY(dbid,rid))"
        )
        con.execute(
            "CREATE TABLE commits("
            "dbid TEXT NOT NULL,"
            "rid TEXT NOT NULL,"
            "tag TEXT NOT NULL,"
            "receipt TEXT NOT NULL,"
            "PRIMARY KEY(dbid,rid))"
        )

    environments[implementation]={
        "folder":folder,
        "database":database,
        "keyfile":keyfile
    }

def invoke(implementation,mode,rid,value=tag):
    config=environments[implementation]
    env=os.environ.copy()

    if implementation=="python":
        env["P08_LAB"]=str(config["folder"])
        command=[
            sys.executable,"-B",str(python),
            mode,identity,rid,value
        ]
    else:
        env["P11C_KEY"]=str(config["keyfile"])
        command=[
            str(rust),
            str(config["database"]),
            mode,identity,rid,value
        ]

    process=subprocess.run(
        command,
        text=True,
        capture_output=True,
        timeout=15,
        env=env
    )

    return {
        "stdout":process.stdout.strip(),
        "exit":process.returncode,
        "stderr_present":bool(process.stderr.strip())
    }

def snapshot(implementation,rid):
    db=environments[implementation]["database"]
    with sqlite3.connect(db) as con:
        claim=con.execute(
            "SELECT tag,state FROM claims "
            "WHERE dbid=? AND rid=?",
            (identity,rid)
        ).fetchone()
        commit=con.execute(
            "SELECT tag,receipt FROM commits "
            "WHERE dbid=? AND rid=?",
            (identity,rid)
        ).fetchone()
        integrity=con.execute(
            "PRAGMA integrity_check"
        ).fetchone()[0]

    return {
        "claim":list(claim) if claim else None,
        "commit":list(commit) if commit else None,
        "integrity":integrity
    }

def compare(label,mode,rid,value=tag):
    responses={}
    states={}

    for implementation in ("python","rust"):
        responses[implementation]=invoke(
            implementation,mode,rid,value
        )
        states[implementation]=snapshot(
            implementation,rid
        )

    response_equal=(
        responses["python"]["stdout"]==
        responses["rust"]["stdout"]
        and responses["python"]["exit"]==
        responses["rust"]["exit"]
    )

    state_equal=states["python"]==states["rust"]

    observation={
        "case":label,
        "mode":mode,
        "response_equal":response_equal,
        "state_equal":state_equal,
        "responses":responses,
        "states":states
    }
    observations.append(observation)

    print(
        f"CASE={label} "
        f"PY={responses['python']['stdout']!r} "
        f"RUST={responses['rust']['stdout']!r} "
        f"RESPONSE_EQUAL={response_equal} "
        f"STATE_EQUAL={state_equal}",
        flush=True
    )

    if not response_equal or not state_equal:
        differences.append(label)

print("=== A. BASIC PROTOCOL ===",flush=True)

compare("unreserved_commit","commit","missing")
compare("first_reserve","reserve","normal")
compare("duplicate_reserve","reserve","normal")
compare("normal_commit","commit","normal")
compare("committed_replay","commit","normal")
compare("conflicting_commit","commit","normal",other)
compare("conflicting_reserve","reserve","normal",other)

print("=== B. INVALID AND STALE STATE ===",flush=True)

compare("invalid_mode","invalid","unused")
compare("commit_without_reservation","commit","other")
compare("reserve_stale","reserve","stale")
compare("commit_stale","commit","stale")

for implementation in ("python","rust"):
    db=environments[implementation]["database"]
    with sqlite3.connect(db) as con:
        con.execute(
            "DELETE FROM commits WHERE dbid=? AND rid=?",
            (identity,"stale")
        )

compare("stale_commit_replay","commit","stale")
compare("stale_reserve_replay","reserve","stale")

print("=== C. CORRUPTED HMAC ===",flush=True)

for implementation in ("python","rust"):
    db=environments[implementation]["database"]
    with sqlite3.connect(db) as con:
        con.execute(
            "UPDATE commits SET receipt=? "
            "WHERE dbid=? AND rid=?",
            ("0"*64,identity,"normal")
        )

compare("tampered_commit_replay","commit","normal")
compare("tampered_reserve_replay","reserve","normal")

print("=== D. RESTORE VALID RECEIPT ===",flush=True)

for implementation in ("python","rust"):
    db=environments[implementation]["database"]
    with sqlite3.connect(db) as con:
        con.execute(
            "UPDATE commits SET receipt=? "
            "WHERE dbid=? AND rid=?",
            (receipt("normal"),identity,"normal")
        )

compare("restored_commit_replay","commit","normal")
compare("restored_reserve_replay","reserve","normal")

print("=== E. INDEPENDENT INTEGRITY ===",flush=True)

for implementation in ("python","rust"):
    db=environments[implementation]["database"]
    with sqlite3.connect(db) as con:
        integrity=con.execute(
            "PRAGMA integrity_check"
        ).fetchone()[0]

    check(implementation+"_sqlite_integrity",
          integrity=="ok")

check("comparison_cases_executed",
      len(observations)==17)

check("both_implementations_executed",
      all(
          "python" in case["responses"]
          and "rust" in case["responses"]
          for case in observations
      ))

response_equal=sum(
    item["response_equal"] for item in observations
)
state_equal=sum(
    item["state_equal"] for item in observations
)

result=(
    "PROTOCOL_EQUIVALENCE_OBSERVED"
    if not differences
    else "PROTOCOL_DIFFERENCES_REQUIRE_REVIEW"
)

report={
    "audit":"ZOS-PRODUCT-01S6B-02P-11J",
    "checks":checks,
    "observations":observations,
    "differences":differences,
    "comparison_cases":len(observations),
    "response_equal":response_equal,
    "state_equal":state_equal,
    "result":result,
    "limitations":[
        "Finite protocol traces, not formal equivalence",
        "Independent SQLite databases with identical key",
        "No multiprocess differential workload",
        "No cross-process isolation",
        "No full-state rollback resistance",
        "No external worker or IPFS execution"
    ],
    "security_acceptance":"BLOCKED",
    "production_status":"NO_GO",
    "network_operations":False,
    "github_mutations":False
}

out=root/"PRODUCT01S6B02P11J_REPORT.json"
out.write_text(json.dumps(report,indent=2)+"\n")

print("=== SUMMARY ===",flush=True)
print(f"COMPARISON_CASES={len(observations)}")
print(f"RESPONSE_EQUAL={response_equal}/17")
print(f"STATE_EQUAL={state_equal}/17")
print(f"DIFFERENCES={len(differences)}")
print(f"RESULT={result}")
print(f"REPORT={out}")

if not all(checks.values()):
    sys.exit(2)
