import hashlib
import hmac
import os
from pathlib import Path
import sqlite3
import sys

root=Path(os.environ["P08_LAB"])
db=root/"canonical.sqlite"
key=(root/"authority.key").read_bytes()

if len(key)!=32:
    sys.exit(3)

def receipt(dbid,rid,tag):
    data=b"ZOS-AUTH-COMMIT-V1\x00"
    for value in (dbid,rid,tag):
        raw=value.encode("ascii")
        data+=len(raw).to_bytes(4,"big")+raw
    return hmac.new(key,data,hashlib.sha256).hexdigest()

def execute(mode,dbid,rid,tag):
    if (
        len(dbid)!=32 or
        any(c not in "0123456789abcdef" for c in dbid) or
        not 1<=len(rid)<=64 or
        any(not(c.isascii() and
                (c.isalnum() or c in "_-"))
            for c in rid) or
        len(tag)!=64 or
        any(c not in "0123456789abcdef" for c in tag)
    ):
        return "INVALID_DENY"

    with sqlite3.connect(db,timeout=15) as con:
        con.execute("PRAGMA busy_timeout=15000")
        con.execute("PRAGMA synchronous=FULL")
        con.execute("BEGIN IMMEDIATE")

        claim=con.execute(
            "SELECT tag,state FROM claims "
            "WHERE dbid=? AND rid=?",
            (dbid,rid)
        ).fetchone()

        row=con.execute(
            "SELECT tag,receipt FROM commits "
            "WHERE dbid=? AND rid=?",
            (dbid,rid)
        ).fetchone()

        if mode=="reserve":
            if claim is None:
                if row is not None:
                    return "ORPHAN_COMMIT_DENY"
                con.execute(
                    "INSERT INTO claims VALUES (?,?,?,?)",
                    (dbid,rid,tag,"CLAIMED")
                )
                return "RESERVED"
            if claim[0]!=tag:
                return "CONFLICT_DENY"
            if claim[1]=="CLAIMED" and row is None:
                return "RESERVATION_EXISTS"
            if claim[1]=="COMMITTED" and row is not None:
                if (row[0]==tag and
                    hmac.compare_digest(
                        row[1],receipt(dbid,rid,tag)
                    )):
                    return "REPLAY"
            return "STATE_MISMATCH_DENY"

        if mode!="commit":
            return "INVALID_MODE_DENY"

        if claim is None:
            return "UNRESERVED_DENY"
        if claim[0]!=tag:
            return "CONFLICT_DENY"

        if claim[1]=="COMMITTED":
            if row is None:
                return "STALE_CANONICAL_DENY"
            if row[0]!=tag or not hmac.compare_digest(
                row[1],receipt(dbid,rid,tag)
            ):
                return "INTEGRITY_DENY"
            return "REPLAY"

        if claim[1]!="CLAIMED" or row is not None:
            return "STATE_MISMATCH_DENY"

        con.execute(
            "INSERT INTO commits VALUES (?,?,?,?)",
            (dbid,rid,tag,receipt(dbid,rid,tag))
        )
        cur=con.execute(
            "UPDATE claims SET state='COMMITTED' "
            "WHERE dbid=? AND rid=? AND tag=? "
            "AND state='CLAIMED'",
            (dbid,rid,tag)
        )
        if cur.rowcount!=1:
            raise RuntimeError("CLAIM_UPDATE_FAILED")
        return "COMMITTED"

if __name__=="__main__":
    if len(sys.argv)!=5:
        sys.exit(3)
    try:
        print(execute(*sys.argv[1:]),flush=True)
    except (sqlite3.Error,OSError,RuntimeError,ValueError):
        print("AUTHORITY_DENY",flush=True)
        sys.exit(3)
