use std::env;
use std::fs;

const K: [u32; 64] = [
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,
    0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,
    0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,
    0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,
    0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,
    0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,
    0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,
    0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,
    0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
];

fn sha256(data: &[u8]) -> String {
    let mut h: [u32; 8] = [
        0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,
        0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19
    ];
    let bit_len = (data.len() as u64).wrapping_mul(8);
    let mut msg = data.to_vec();
    msg.push(0x80);
    while msg.len() % 64 != 56 {
        msg.push(0);
    }
    msg.extend_from_slice(&bit_len.to_be_bytes());

    for chunk in msg.chunks_exact(64) {
        let mut w = [0u32; 64];
        for i in 0..16 {
            w[i] = u32::from_be_bytes(
                chunk[4*i..4*i+4].try_into().unwrap()
            );
        }
        for i in 16..64 {
            let x = w[i-15];
            let y = w[i-2];
            let s0 = x.rotate_right(7)
                ^ x.rotate_right(18) ^ (x >> 3);
            let s1 = y.rotate_right(17)
                ^ y.rotate_right(19) ^ (y >> 10);
            w[i] = w[i-16].wrapping_add(s0)
                .wrapping_add(w[i-7])
                .wrapping_add(s1);
        }
        let mut v = h;
        for i in 0..64 {
            let s1 = v[4].rotate_right(6)
                ^ v[4].rotate_right(11)
                ^ v[4].rotate_right(25);
            let ch = (v[4] & v[5]) ^ (!v[4] & v[6]);
            let t1 = v[7].wrapping_add(s1)
                .wrapping_add(ch)
                .wrapping_add(K[i])
                .wrapping_add(w[i]);
            let s0 = v[0].rotate_right(2)
                ^ v[0].rotate_right(13)
                ^ v[0].rotate_right(22);
            let maj = (v[0] & v[1])
                ^ (v[0] & v[2])
                ^ (v[1] & v[2]);
            let t2 = s0.wrapping_add(maj);
            v[7] = v[6];
            v[6] = v[5];
            v[5] = v[4];
            v[4] = v[3].wrapping_add(t1);
            v[3] = v[2];
            v[2] = v[1];
            v[1] = v[0];
            v[0] = t1.wrapping_add(t2);
        }
        for i in 0..8 {
            h[i] = h[i].wrapping_add(v[i]);
        }
    }
    h.iter().map(|x| format!("{x:08x}")).collect()
}

// Restricted to the two fixed account identifiers
// used in this isolated accounting model.
// A general JSON serializer is NOT implemented here.
fn fingerprint(src: &str, dst: &str, amount: i64)
    -> Option<String>
{
    if !["alice", "treasury"].contains(&src)
        || !["alice", "treasury"].contains(&dst)
        || amount < 1 || amount > 1_000_000
    {
        return None;
    }
    let payload = format!(
        "[\"{}\",\"{}\",{}]", src, dst, amount
    );
    Some(sha256(payload.as_bytes()))
}

#[derive(Debug, PartialEq, Eq)]
enum Decision {
    New,
    Replay,
    Conflict,
    IntegrityError,
}

fn decide(
    stored: Option<(&str, &str, i64, &str, Option<&str>)>,
    requested: (&str, &str, i64),
) -> Decision {
    let Some((src, dst, amount, stored_fp, outbox_fp)) =
        stored
    else {
        return Decision::New;
    };

    let Some(expected_fp) = fingerprint(src, dst, amount)
    else {
        return Decision::IntegrityError;
    };

    // Integrity must be checked BEFORE replay equality.
    if stored_fp != expected_fp
        || outbox_fp != Some(expected_fp.as_str())
    {
        return Decision::IntegrityError;
    }

    if (src, dst, amount) == requested {
        Decision::Replay
    } else {
        Decision::Conflict
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sha256_known_vectors() {
        assert_eq!(
            sha256(b""),
            "e3b0c44298fc1c149afbf4c8996fb924"
            .to_owned() +
            "27ae41e4649b934ca495991b7852b855"
        );
        assert_eq!(
            sha256(b"abc"),
            "ba7816bf8f01cfea414140de5dae2223"
            .to_owned() +
            "b00361a396177a9cb410ff61f20015ad"
        );
    }

    #[test]
    fn content_identity_is_checked() {
        let fp = fingerprint(
            "treasury", "alice", 2
        ).unwrap();

        let stored = Some((
            "treasury", "alice", 2,
            fp.as_str(), Some(fp.as_str())
        ));

        assert_eq!(
            decide(stored, ("treasury", "alice", 2)),
            Decision::Replay
        );
        assert_eq!(
            decide(stored, ("treasury", "alice", 3)),
            Decision::Conflict
        );
        assert_eq!(
            decide(stored, ("alice", "treasury", 2)),
            Decision::Conflict
        );
        assert_eq!(
            decide(None, ("treasury", "alice", 1)),
            Decision::New
        );
    }

    #[test]
    fn forged_fingerprint_fails_closed() {
        let bad = "0".repeat(64);
        assert_eq!(
            decide(
                Some((
                    "treasury", "alice", 2,
                    bad.as_str(), Some(bad.as_str())
                )),
                ("treasury", "alice", 2)
            ),
            Decision::IntegrityError
        );
    }
}


// ZOS-REUSE-04F: read-only SQLite integration.
// All economic identity decisions use the original
// 04E Rust decide() function.

use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int, c_void};
use std::ptr;

#[repr(C)]
struct sqlite3 {
    _private: [u8; 0],
}

#[repr(C)]
struct sqlite3_stmt {
    _private: [u8; 0],
}

unsafe extern "C" {
    fn sqlite3_open_v2(
        filename: *const c_char,
        db: *mut *mut sqlite3,
        flags: c_int,
        vfs: *const c_char,
    ) -> c_int;

    fn sqlite3_close(db: *mut sqlite3) -> c_int;

    fn sqlite3_db_readonly(
        db: *mut sqlite3,
        name: *const c_char,
    ) -> c_int;

    fn sqlite3_prepare_v2(
        db: *mut sqlite3,
        sql: *const c_char,
        bytes: c_int,
        stmt: *mut *mut sqlite3_stmt,
        tail: *mut *const c_char,
    ) -> c_int;

    fn sqlite3_bind_text(
        stmt: *mut sqlite3_stmt,
        index: c_int,
        value: *const c_char,
        len: c_int,
        destructor: Option<unsafe extern "C" fn(*mut c_void)>,
    ) -> c_int;

    fn sqlite3_step(stmt: *mut sqlite3_stmt) -> c_int;
    fn sqlite3_finalize(stmt: *mut sqlite3_stmt) -> c_int;
    fn sqlite3_column_type(
        stmt: *mut sqlite3_stmt,
        column: c_int,
    ) -> c_int;
    fn sqlite3_column_text(
        stmt: *mut sqlite3_stmt,
        column: c_int,
    ) -> *const u8;
    fn sqlite3_column_bytes(
        stmt: *mut sqlite3_stmt,
        column: c_int,
    ) -> c_int;
    fn sqlite3_column_int64(
        stmt: *mut sqlite3_stmt,
        column: c_int,
    ) -> i64;
    fn sqlite3_errmsg(db: *mut sqlite3) -> *const c_char;
}

const SQLITE_OK: c_int = 0;
const SQLITE_ROW: c_int = 100;
const SQLITE_DONE: c_int = 101;
const SQLITE_NULL: c_int = 5;
const SQLITE_OPEN_READONLY: c_int = 1;

struct Db(*mut sqlite3);

impl Drop for Db {
    fn drop(&mut self) {
        if !self.0.is_null() {
            unsafe {
                let _ = sqlite3_close(self.0);
            }
        }
    }
}

struct Statement(*mut sqlite3_stmt);

impl Drop for Statement {
    fn drop(&mut self) {
        if !self.0.is_null() {
            unsafe {
                let _ = sqlite3_finalize(self.0);
            }
        }
    }
}

fn error(db: *mut sqlite3) -> String {
    unsafe {
        if db.is_null() {
            return "SQLite null database handle".into();
        }
        CStr::from_ptr(sqlite3_errmsg(db))
            .to_string_lossy()
            .into_owned()
    }
}

fn open_readonly(path: &str) -> Db {
    let filename = CString::new(path).unwrap();
    let mut raw = ptr::null_mut();

    let rc = unsafe {
        sqlite3_open_v2(
            filename.as_ptr(),
            &mut raw,
            SQLITE_OPEN_READONLY,
            ptr::null(),
        )
    };

    let db = Db(raw);

    assert_eq!(
        rc, SQLITE_OK,
        "SQLite readonly open failed: {}",
        error(raw)
    );

    let main = CString::new("main").unwrap();
    let readonly = unsafe {
        sqlite3_db_readonly(raw, main.as_ptr())
    };

    assert_eq!(readonly, 1);
    db
}

fn column_string(
    stmt: *mut sqlite3_stmt,
    index: c_int,
) -> Option<String> {
    unsafe {
        if sqlite3_column_type(stmt, index) == SQLITE_NULL {
            return None;
        }

        let len = sqlite3_column_bytes(stmt, index);
        assert!(len >= 0);

        let ptr = sqlite3_column_text(stmt, index);
        assert!(!ptr.is_null());

        let bytes = std::slice::from_raw_parts(
            ptr, len as usize
        );

        Some(
            std::str::from_utf8(bytes)
                .expect("invalid SQLite UTF-8")
                .to_string()
        )
    }
}

#[derive(Debug)]
struct Stored {
    src: String,
    dst: String,
    amount: i64,
    fingerprint: String,
    outbox: Option<String>,
}

fn lookup(db: &Db, txid: &str) -> Option<Stored> {
    let sql = CString::new(
        "SELECT t.src,t.dst,t.amount,t.fingerprint,\
                o.payload \
         FROM transfers AS t \
         LEFT JOIN outbox AS o ON o.id=t.id \
         WHERE t.id=?1"
    ).unwrap();

    let mut raw_stmt = ptr::null_mut();

    let rc = unsafe {
        sqlite3_prepare_v2(
            db.0,
            sql.as_ptr(),
            -1,
            &mut raw_stmt,
            ptr::null_mut(),
        )
    };
    let stmt = Statement(raw_stmt);

    assert_eq!(rc, SQLITE_OK, "{}", error(db.0));

    let key = CString::new(txid).unwrap();
    let bind_rc = unsafe {
        sqlite3_bind_text(
            stmt.0,
            1,
            key.as_ptr(),
            txid.len() as c_int,
            None,
        )
    };
    assert_eq!(bind_rc, SQLITE_OK);

    let step = unsafe { sqlite3_step(stmt.0) };

    if step == SQLITE_DONE {
        return None;
    }

    assert_eq!(step, SQLITE_ROW, "{}", error(db.0));

    let record = Stored {
        src: column_string(stmt.0, 0).unwrap(),
        dst: column_string(stmt.0, 1).unwrap(),
        amount: unsafe {
            sqlite3_column_int64(stmt.0, 2)
        },
        fingerprint: column_string(stmt.0, 3).unwrap(),
        outbox: column_string(stmt.0, 4),
    };

    let second = unsafe { sqlite3_step(stmt.0) };
    assert_eq!(
        second, SQLITE_DONE,
        "duplicate transaction ID or SQLite read error"
    );

    Some(record)
}

fn txid_for(label: &str) -> &'static str {
    match label {
        "REPLAY_TX_A"
        | "CONFLICT_AMOUNT"
        | "CONFLICT_SOURCE"
        | "CONFLICT_DESTINATION"
        | "TAMPERED_EXACT"
        | "TAMPERED_CHANGED" => "tx-a",

        "REPLAY_TX_B" => "tx-b",
        "REPLAY_TX_C" => "tx-c",
        "NEW_ID" => "nonexistent-04e",

        _ => panic!("unknown fixture label: {label}"),
    }
}


const SQLITE_OPEN_READWRITE: c_int = 2;

unsafe extern "C" {
    fn sqlite3_exec(
        db: *mut sqlite3,
        sql: *const c_char,
        callback: Option<
            unsafe extern "C" fn(
                *mut c_void,
                c_int,
                *mut *mut c_char,
                *mut *mut c_char
            ) -> c_int
        >,
        arg: *mut c_void,
        err: *mut *mut c_char,
    ) -> c_int;

    fn sqlite3_bind_int64(
        stmt: *mut sqlite3_stmt,
        index: c_int,
        value: i64,
    ) -> c_int;

    fn sqlite3_column_int(
        stmt: *mut sqlite3_stmt,
        column: c_int,
    ) -> c_int;
}

fn open_readwrite(path: &str) -> Db {
    let filename = CString::new(path).unwrap();
    let mut raw = ptr::null_mut();

    let rc = unsafe {
        sqlite3_open_v2(
            filename.as_ptr(),
            &mut raw,
            SQLITE_OPEN_READWRITE,
            ptr::null(),
        )
    };

    let db = Db(raw);
    assert_eq!(rc, SQLITE_OK, "{}", error(raw));

    let main = CString::new("main").unwrap();
    assert_eq!(
        unsafe { sqlite3_db_readonly(raw, main.as_ptr()) },
        0
    );

    db
}

fn sql_exec(db: &Db, command: &str) -> Result<(), String> {
    let sql = CString::new(command).unwrap();

    let rc = unsafe {
        sqlite3_exec(
            db.0,
            sql.as_ptr(),
            None,
            ptr::null_mut(),
            ptr::null_mut(),
        )
    };

    if rc == SQLITE_OK {
        Ok(())
    } else {
        Err(error(db.0))
    }
}

struct Transaction<'a> {
    db: &'a Db,
    active: bool,
}

impl<'a> Transaction<'a> {
    fn begin(db: &'a Db) -> Self {
        sql_exec(db, "BEGIN IMMEDIATE")
            .expect("BEGIN IMMEDIATE failed");

        Self { db, active: true }
    }

    fn commit(mut self) {
        sql_exec(self.db, "COMMIT")
            .expect("COMMIT failed");
        self.active = false;
    }
}

impl Drop for Transaction<'_> {
    fn drop(&mut self) {
        if self.active {
            let _ = sql_exec(self.db, "ROLLBACK");
        }
    }
}

fn bind_text(
    stmt: *mut sqlite3_stmt,
    index: c_int,
    text: &CString,
) {
    let rc = unsafe {
        sqlite3_bind_text(
            stmt,
            index,
            text.as_ptr(),
            text.as_bytes().len() as c_int,
            None,
        )
    };

    assert_eq!(rc, SQLITE_OK);
}

fn insert_transfer(
    db: &Db,
    id: &str,
    src: &str,
    dst: &str,
    amount: i64,
) -> Result<(), String> {
    let fingerprint = fingerprint(src, dst, amount)
        .ok_or_else(|| "INVALID_PAYLOAD".to_string())?;

    let sql = CString::new(
        "INSERT INTO transfers \
         (id,src,dst,amount,fingerprint) \
         VALUES (?1,?2,?3,?4,?5)"
    ).unwrap();

    let mut raw_stmt = ptr::null_mut();

    let rc = unsafe {
        sqlite3_prepare_v2(
            db.0,
            sql.as_ptr(),
            -1,
            &mut raw_stmt,
            ptr::null_mut(),
        )
    };

    let stmt = Statement(raw_stmt);

    if rc != SQLITE_OK {
        return Err(error(db.0));
    }

    let id_c = CString::new(id).map_err(
        |_| "INVALID_ID_NUL".to_string()
    )?;
    let src_c = CString::new(src).unwrap();
    let dst_c = CString::new(dst).unwrap();
    let fingerprint_c = CString::new(fingerprint).unwrap();

    // CString values stay alive until sqlite3_step.
    bind_text(stmt.0, 1, &id_c);
    bind_text(stmt.0, 2, &src_c);
    bind_text(stmt.0, 3, &dst_c);

    let rc = unsafe {
        sqlite3_bind_int64(stmt.0, 4, amount)
    };
    assert_eq!(rc, SQLITE_OK);

    bind_text(stmt.0, 5, &fingerprint_c);

    let rc = unsafe { sqlite3_step(stmt.0) };

    if rc == SQLITE_DONE {
        Ok(())
    } else {
        Err(error(db.0))
    }
}

fn valid_id(id: &str) -> bool {
    !id.is_empty()
        && id.len() <= 128
        && id.is_ascii()
}

fn execute(
    db: &Db,
    id: &str,
    src: &str,
    dst: &str,
    amount: i64,
) -> &'static str {
    if !valid_id(id)
        || src == dst
        || !["alice", "treasury"].contains(&src)
        || !["alice", "treasury"].contains(&dst)
        || !(1..=1_000_000).contains(&amount)
    {
        return "Invalid";
    }

    let tx = Transaction::begin(db);

    if let Some(record) = lookup(db, id) {
        let result = decide(
            Some((
                &record.src,
                &record.dst,
                record.amount,
                &record.fingerprint,
                record.outbox.as_deref(),
            )),
            (src, dst, amount),
        );

        // Transaction automatically rolls back on drop.
        return match result {
            Decision::Replay => "Replay",
            Decision::Conflict => "Conflict",
            Decision::IntegrityError => "IntegrityError",
            Decision::New => "IntegrityError",
        };
    }

    match insert_transfer(db, id, src, dst, amount) {
        Ok(()) => {
            tx.commit();
            "Committed"
        }
        Err(reason) => {
            if reason.contains("INSUFFICIENT") {
                "Insufficient"
            } else if reason.contains("CREDIT_OVERFLOW") {
                "Overflow"
            } else {
                panic!("Unexpected SQLite insert failure: {reason}")
            }
        }
    }
}

fn count_rows(db: &Db, table: &str) -> i64 {
    assert!(["transfers", "outbox"].contains(&table));

    let query = CString::new(
        format!("SELECT COUNT(*) FROM {table}")
    ).unwrap();

    let mut raw_stmt = ptr::null_mut();

    assert_eq!(
        unsafe {
            sqlite3_prepare_v2(
                db.0,
                query.as_ptr(),
                -1,
                &mut raw_stmt,
                ptr::null_mut(),
            )
        },
        SQLITE_OK
    );

    let stmt = Statement(raw_stmt);
    assert_eq!(unsafe { sqlite3_step(stmt.0) }, SQLITE_ROW);

    let count = unsafe {
        sqlite3_column_int64(stmt.0, 0)
    };

    assert_eq!(unsafe { sqlite3_step(stmt.0) }, SQLITE_DONE);
    count
}

fn main() {
    let path = std::env::args()
        .nth(1)
        .expect("SQLite copy path required");

    let db = open_readwrite(&path);
    sql_exec(&db, "PRAGMA foreign_keys=ON")
        .expect("foreign keys");
    sql_exec(&db, "PRAGMA busy_timeout=2500")
        .expect("busy timeout");

    assert_eq!(count_rows(&db, "transfers"), 0);
    assert_eq!(count_rows(&db, "outbox"), 0);

    println!("PASS SQLITE_NATIVE_READWRITE_COPY");

    let cases = [
        ("COMMIT_A", "tx-a", "treasury", "alice", 2, "Committed"),
        ("REPLAY_A", "tx-a", "treasury", "alice", 2, "Replay"),
        ("AMOUNT_CONFLICT", "tx-a", "treasury", "alice", 3, "Conflict"),
        ("DIRECTION_CONFLICT", "tx-a", "alice", "treasury", 2, "Conflict"),
        ("INSUFFICIENT_B", "tx-b", "treasury", "alice", 9, "Insufficient"),
        ("COMMIT_B", "tx-b", "treasury", "alice", 8, "Committed"),
        ("COMMIT_C", "tx-c", "alice", "treasury", 1, "Committed"),
        ("REPLAY_A_AGAIN", "tx-a", "treasury", "alice", 2, "Replay"),
        ("INVALID_ID", "", "treasury", "alice", 1, "Invalid"),
    ];

    for (label, id, src, dst, amount, expected) in cases {
        let actual = execute(
            &db, id, src, dst, amount
        );

        assert_eq!(actual, expected, "{label}");

        let transfers = count_rows(&db, "transfers");
        let outbox = count_rows(&db, "outbox");

        assert_eq!(transfers, outbox);

        println!(
            "PASS {label} {actual} \
             transfers={transfers} outbox={outbox}"
        );
    }

    assert_eq!(count_rows(&db, "transfers"), 3);
    assert_eq!(count_rows(&db, "outbox"), 3);

    // SQLite must persist all committed transactions.
    drop(db);

    let reopened = open_readonly(&path);
    assert_eq!(count_rows(&reopened, "transfers"), 3);
    assert_eq!(count_rows(&reopened, "outbox"), 3);

    println!("PASS REOPEN_COMMITTED_STATE");
    println!("TRANSACTIONAL_STEPS=9");
    println!("NATIVE_RUST_SQLITE_COMMIT=PASS");
}
