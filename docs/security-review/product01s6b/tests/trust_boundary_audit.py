import hashlib
import hmac
import json
import os
from pathlib import Path
import secrets
import shutil
import sqlite3
import subprocess
import sys

root=Path(os.environ["P11K_LAB"])
rust=Path(os.environ["P11K_RUST"])
python=Path(os.environ["P11K_PYTHON"])

identity=secrets.token_hex(16)
tag="ab"*32
key=secrets.token_bytes(32)

checks={}
observations={}

def check(name,condition):
    ok=bool(condition)
    checks[name]=ok
    print(f"CHECK={name} PASS={ok}",flush=True)
    if not ok:
        raise AssertionError(name)

def receipt(rid):
    message=b"ZOS-AUTH-COMMIT-V1\x00"
    for value in (identity,rid,tag):
        raw=value.encode("ascii")
        message+=len(raw).to_bytes(4,"big")+raw
    return hmac.new(
        key,message,hashlib.sha256
    ).hexdigest()

def create_environment(implementation):
    folder=root/implementation
    folder.mkdir()
    db=folder/"canonical.sqlite"
    keyfile=folder/"authority.key"

    keyfile.write_bytes(key)
    keyfile.chmod(0o600)

    with sqlite3.connect(db) as con:
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

    return folder,db,keyfile

def invoke(implementation,folder,db,keyfile,mode,rid):
    env=os.environ.copy()
    if implementation=="rust":
        env["P11C_KEY"]=str(keyfile)
        command=[
            str(rust),str(db),
            mode,identity,rid,tag
        ]
    else:
        env["P08_LAB"]=str(folder)
        command=[
            sys.executable,"-B",str(python),
            mode,identity,rid,tag
        ]

    result=subprocess.run(
        command,
        env=env,
        capture_output=True,
        text=True,
        timeout=15
    )

    return result.stdout.strip(),result.returncode

def state(db,rid):
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

    return claim,commit,integrity

for implementation in ("python","rust"):
    print(
        f"=== IMPLEMENTATION={implementation} ===",
        flush=True
    )

    folder,db,keyfile=create_environment(implementation)

    def call(mode,rid):
        return invoke(
            implementation,folder,db,keyfile,
            mode,rid
        )

    prefix=implementation

    print("=== A. COMPLETE DATABASE ROLLBACK ===",
          flush=True)

    rid="rollback_case"

    check(prefix+"_reservation",
          call("reserve",rid)==("RESERVED",0))

    check(prefix+"_precommit_state",
          state(db,rid)==((tag,"CLAIMED"),None,"ok"))

    # Capture a consistent SQLite image before COMMIT.
    # No SQLite connection remains open during replacement.
    snapshot=folder/"precommit.snapshot.sqlite"
    with sqlite3.connect(db) as source:
        with sqlite3.connect(snapshot) as target:
            source.backup(target)

    check(prefix+"_snapshot_created",snapshot.is_file())

    check(prefix+"_first_commit",
          call("commit",rid)==("COMMITTED",0))

    before=state(db,rid)

    check(prefix+"_first_receipt_valid",
          before==(
              (tag,"COMMITTED"),
              (tag,receipt(rid)),
              "ok"
          ))

    # Experimental rollback: restore the complete
    # pre-COMMIT database image. No external effects run.
    shutil.copyfile(snapshot,db)

    check(prefix+"_rollback_state",
          state(db,rid)==((tag,"CLAIMED"),None,"ok"))

    second=call("commit",rid)

    print(
        f"ROLLBACK_RECOMMIT={implementation} "
        f"RESULT={second}",
        flush=True
    )

    check(prefix+"_second_commit_accepted",
          second==("COMMITTED",0))

    check(prefix+"_second_receipt_valid",
          state(db,rid)==(
              (tag,"COMMITTED"),
              (tag,receipt(rid)),
              "ok"
          ))

    check(prefix+"_later_replay",
          call("commit",rid)==("REPLAY",0))

    observations[prefix+"_rollback"]={
        "first_commit":"COMMITTED",
        "database_restored_to_precommit":True,
        "second_commit":second[0],
        "external_effects_executed":False
    }

    print("=== B. SAME-UID CANONICAL FORGERY ===",
          flush=True)

    forged="forged_case"

    check(prefix+"_forged_case_initially_absent",
          state(db,forged)==(None,None,"ok"))

    # Simulate a process that can modify both
    # the SQLite database and read the HMAC key.
    # Do not invoke authority.reserve/commit here.
    with sqlite3.connect(db) as con:
        con.execute("BEGIN IMMEDIATE")
        con.execute(
            "INSERT INTO claims(dbid,rid,tag,state) "
            "VALUES(?,?,?,'COMMITTED')",
            (identity,forged,tag)
        )
        con.execute(
            "INSERT INTO commits(dbid,rid,tag,receipt) "
            "VALUES(?,?,?,?)",
            (identity,forged,tag,receipt(forged))
        )

    check(prefix+"_forged_state_well_formed",
          state(db,forged)==(
              (tag,"COMMITTED"),
              (tag,receipt(forged)),
              "ok"
          ))

    replay=call("commit",forged)

    print(
        f"SAME_UID_FORGERY={implementation} "
        f"RESULT={replay}",
        flush=True
    )

    check(prefix+"_forged_state_accepted_as_replay",
          replay==("REPLAY",0))

    check(prefix+"_forged_state_unchanged",
          state(db,forged)==(
              (tag,"COMMITTED"),
              (tag,receipt(forged)),
              "ok"
          ))

    observations[prefix+"_forgery"]={
        "created_without_authority":True,
        "receipt_computed_with_accessible_key":True,
        "authority_response":replay[0],
        "external_effects_executed":False
    }

print("=== C. CROSS-IMPLEMENTATION COMPARISON ===",
      flush=True)

check(
    "rollback_behavior_equal",
    observations["python_rollback"]["second_commit"]==
    observations["rust_rollback"]["second_commit"]
)

check(
    "forgery_behavior_equal",
    observations["python_forgery"]["authority_response"]==
    observations["rust_forgery"]["authority_response"]
)

check(
    "all_negative_controls_observed",
    len(observations)==4
)

status=(
    "EXPECTED_TRUST_BOUNDARY_GAPS_REPRODUCED"
    if all(checks.values())
    else "REVIEW_REQUIRED"
)

report={
    "audit":"ZOS-PRODUCT-01S6B-02P-11K",
    "checks":checks,
    "passed":sum(checks.values()),
    "total":len(checks),
    "observations":observations,
    "result":status,
    "findings":[
        {
            "id":"TRUST-ROLLBACK",
            "severity":"HIGH",
            "status":"REPRODUCED",
            "description":
                "Restoring a precommit SQLite image permits "
                "another COMMITTED response for the same identity"
        },
        {
            "id":"TRUST-SAME-UID",
            "severity":"HIGH",
            "status":"REPRODUCED",
            "description":
                "A process with write access to SQLite and "
                "access to the HMAC key can forge canonical "
                "COMMITTED state that is accepted as REPLAY"
        }
    ],
    "limitations":[
        "No external worker or IPFS effects executed",
        "Second COMMITTED is not proof of duplicate side effects",
        "Same-UID capability deliberately simulated",
        "No different-UID privilege separation test",
        "No power-loss or kernel-level filesystem fault test",
        "No production integration"
    ],
    "security_acceptance":"BLOCKED",
    "production_status":"NO_GO",
    "github_mutations":False,
    "network_operations":False
}

out=root/"PRODUCT01S6B02P11K_REPORT.json"
out.write_text(json.dumps(report,indent=2)+"\n")

print("=== SUMMARY ===",flush=True)
print(f"CHECKS={report['passed']}/{report['total']}")
print(f"RESULT={status}")
print("TRUST_GAPS_REPRODUCED=2")
print(f"REPORT={out}")

if status!="EXPECTED_TRUST_BOUNDARY_GAPS_REPRODUCED":
    sys.exit(2)
