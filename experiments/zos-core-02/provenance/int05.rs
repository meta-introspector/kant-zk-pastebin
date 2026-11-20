// INT05-RUST-13A: isolated experimental SQLite concurrency worker.
// No token signature validation. Not a production authority.

use std::env;
use std::fs;
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int, c_void};
use std::ptr;

#[repr(C)]
struct RawDb { _private: [u8; 0] }
#[repr(C)]
struct RawStmt { _private: [u8; 0] }

#[link(name = "sqlite3")]
unsafe extern "C" {
    fn sqlite3_open_v2(
        path: *const c_char, out: *mut *mut RawDb,
        flags: c_int, vfs: *const c_char
    ) -> c_int;
    fn sqlite3_close(db: *mut RawDb) -> c_int;
    fn sqlite3_exec(
        db: *mut RawDb, sql: *const c_char,
        cb: Option<unsafe extern "C" fn(
            *mut c_void, c_int, *mut *mut c_char,
            *mut *mut c_char
        ) -> c_int>,
        arg: *mut c_void, err: *mut *mut c_char
    ) -> c_int;
    fn sqlite3_free(ptr: *mut c_void);
    fn sqlite3_errmsg(db: *mut RawDb) -> *const c_char;
    fn sqlite3_prepare_v2(
        db: *mut RawDb, sql: *const c_char, n: c_int,
        out: *mut *mut RawStmt, tail: *mut *const c_char
    ) -> c_int;
    fn sqlite3_bind_text(
        stmt: *mut RawStmt, index: c_int, value: *const c_char,
        n: c_int,
        destructor: Option<unsafe extern "C" fn(*mut c_void)>
    ) -> c_int;
    fn sqlite3_step(stmt: *mut RawStmt) -> c_int;
    fn sqlite3_column_int64(stmt: *mut RawStmt, i: c_int) -> i64;
    fn sqlite3_column_text(stmt: *mut RawStmt, i: c_int) -> *const u8;
    fn sqlite3_column_bytes(stmt: *mut RawStmt, i: c_int) -> c_int;
    fn sqlite3_finalize(stmt: *mut RawStmt) -> c_int;
    fn sqlite3_changes(db: *mut RawDb) -> c_int;
}

const OK: i32 = 0;
const ROW: i32 = 100;
const DONE: i32 = 101;

struct Db(*mut RawDb);
struct Stmt(*mut RawStmt);

impl Drop for Db {
    fn drop(&mut self) {
        if !self.0.is_null() {
            let _ = unsafe { sqlite3_close(self.0) };
        }
    }
}

impl Drop for Stmt {
    fn drop(&mut self) {
        if !self.0.is_null() {
            // A failed step may cause finalize to repeat the error.
            let _ = unsafe { sqlite3_finalize(self.0) };
        }
    }
}

impl Db {
    fn open(path: &str) -> Result<Self, String> {
        let path = CString::new(path).map_err(|e| e.to_string())?;
        let mut raw = ptr::null_mut();
        let rc = unsafe {
            sqlite3_open_v2(path.as_ptr(), &mut raw, 6, ptr::null())
        };
        if rc != OK || raw.is_null() {
            if !raw.is_null() {
                unsafe { sqlite3_close(raw); }
            }
            return Err(format!("OPEN:{rc}"));
        }
        Ok(Self(raw))
    }

    fn error(&self, label: &str, rc: i32) -> String {
        let message = unsafe {
            CStr::from_ptr(sqlite3_errmsg(self.0))
                .to_string_lossy().into_owned()
        };
        format!("{label}:{rc}:{message}")
    }

    fn exec(&self, sql: &str) -> Result<(), String> {
        let sql = CString::new(sql).map_err(|e| e.to_string())?;
        let mut msg = ptr::null_mut();
        let rc = unsafe {
            sqlite3_exec(
                self.0, sql.as_ptr(), None,
                ptr::null_mut(), &mut msg
            )
        };
        let details = if msg.is_null() {
            String::new()
        } else {
            let s = unsafe {
                CStr::from_ptr(msg).to_string_lossy().into_owned()
            };
            unsafe { sqlite3_free(msg.cast()); }
            s
        };
        if rc != OK {
            return Err(format!("EXEC:{rc}:{details}"));
        }
        Ok(())
    }

    fn text(&self, sql: &str, value: &str)
        -> Result<Option<String>, String>
    {
        let statement = CString::new(sql)
            .map_err(|e| e.to_string())?;
        let binding = CString::new(value)
            .map_err(|e| e.to_string())?;
        let mut raw = ptr::null_mut();
        let rc = unsafe {
            sqlite3_prepare_v2(
                self.0, statement.as_ptr(), -1,
                &mut raw, ptr::null_mut()
            )
        };
        if rc != OK {
            return Err(self.error("TEXT_PREPARE", rc));
        }
        if raw.is_null() {
            return Err("TEXT_EMPTY_STATEMENT".into());
        }
        let stmt = Stmt(raw);
        let rc = unsafe {
            sqlite3_bind_text(
                stmt.0, 1, binding.as_ptr(),
                i32::try_from(value.len())
                    .map_err(|e| e.to_string())?,
                None
            )
        };
        if rc != OK {
            return Err(self.error("TEXT_BIND", rc));
        }
        match unsafe { sqlite3_step(stmt.0) } {
            DONE => Ok(None),
            ROW => {
                let ptr = unsafe { sqlite3_column_text(stmt.0, 0) };
                if ptr.is_null() {
                    return Err("NULL_ISSUER_KEY".into());
                }
                let len = unsafe { sqlite3_column_bytes(stmt.0, 0) };
                if len < 0 {
                    return Err("NEGATIVE_TEXT_LENGTH".into());
                }
                let bytes = unsafe {
                    std::slice::from_raw_parts(ptr, len as usize)
                };
                let result = std::str::from_utf8(bytes)
                    .map_err(|e| e.to_string())?;
                Ok(Some(result.to_owned()))
            }
            rc => Err(self.error("TEXT_STEP", rc)),
        }
    }

    fn query(
        &self, sql: &str, params: &[&str]
    ) -> Result<(Option<i64>, i32), String> {
        let sql = CString::new(sql).map_err(|e| e.to_string())?;
        let mut raw = ptr::null_mut();
        let rc = unsafe {
            sqlite3_prepare_v2(
                self.0, sql.as_ptr(), -1,
                &mut raw, ptr::null_mut()
            )
        };
        if rc != OK {
            return Err(self.error("PREPARE", rc));
        }
        if raw.is_null() {
            return Err("EMPTY_STATEMENT".into());
        }
        let stmt = Stmt(raw);
        let owned: Vec<CString> = params.iter()
            .map(|p| CString::new(*p).map_err(|e| e.to_string()))
            .collect::<Result<_, _>>()?;

        for (i, value) in owned.iter().enumerate() {
            let n = i32::try_from(value.as_bytes().len())
                .map_err(|e| e.to_string())?;
            let rc = unsafe {
                sqlite3_bind_text(
                    stmt.0,
                    i32::try_from(i + 1).map_err(|e| e.to_string())?,
                    value.as_ptr(), n, None
                )
            };
            if rc != OK {
                return Err(self.error("BIND", rc));
            }
        }

        let rc = unsafe { sqlite3_step(stmt.0) };
        if rc != ROW && rc != DONE {
            return Err(self.error("STEP", rc));
        }
        let result = if rc == ROW {
            Some(unsafe { sqlite3_column_int64(stmt.0, 0) })
        } else {
            None
        };
        let changed = unsafe { sqlite3_changes(self.0) };
        Ok((result, changed))
    }
}

fn admission(
    db: &Db, id: &str, room: &str, token: &str,
    limit: i64, epoch: i64, signature: &[u8]
) -> Result<&'static str, String> {
    let room = room.to_owned();
    let token = token.to_owned();
    let limit_text = limit.to_string();
    let epoch_text = epoch.to_string();
    let payload = r#"["concurrent"]"#;

    // All authorization inputs are fixed trusted fixtures.
    // No cryptographic verification is performed.
    db.exec("BEGIN IMMEDIATE")?;

    let result = (|| -> Result<&'static str, String> {
        if !valid_hex(&room, 64)
            || !valid_hex(&token, 32)
            || limit <= 0 || epoch <= 0
        {
            return Ok("UNAUTHORIZED");
        }
        let (active_epoch, _) = db.query(
            "SELECT epoch FROM v2_rooms WHERE room=?1",
            &[&room],
        )?;
        let issuer = db.text(
            "SELECT issuer_key FROM v2_rooms WHERE room=?1",
            &room,
        )?;
        if active_epoch != Some(epoch) {
            return Ok("UNAUTHORIZED");
        }
        let Some(issuer) = issuer else {
            return Ok("UNAUTHORIZED");
        };
        if !crypto::verify_claims(
            &issuer, &room, &token, limit, epoch, signature
        )? {
            return Ok("UNAUTHORIZED");
        }
        let (existing, _) = db.query(
            "SELECT COUNT(*) FROM v2_outbox WHERE publication_id=?1",
            &[id],
        )?;
        if existing != Some(0) {
            let (matching, _) = db.query(
                "SELECT COUNT(*) FROM v2_outbox \
                 WHERE publication_id=?1 AND room=?2 \
                 AND epoch=CAST(?5 AS INTEGER) AND token_id=?3 \
                 AND payload_json=?4 AND line_count=1",
                &[id, &room, &token, payload, &epoch_text],
            )?;
            return Ok(if matching == Some(1) {
                "DUPLICATE"
            } else {
                "CONFLICT"
            });
        }

        let (_, changed) = db.query(
            "UPDATE v2_spends SET spent=spent+1 \
             WHERE room=?1 AND epoch=CAST(?4 AS INTEGER) AND token_id=?2 \
             AND limit_max=CAST(?3 AS INTEGER) AND spent<=limit_max-1",
            &[&room, &token, &limit_text, &epoch_text],
        )?;
        if changed != 1 {
            return Ok("QUOTA_EXHAUSTED");
        }
        inject_sigkill("AFTER_QUOTA_BEFORE_INSERT");

        let (_, changed) = db.query(
            "INSERT INTO v2_outbox \
             (publication_id,room,epoch,token_id,payload_json,line_count) \
             VALUES (?1,?2,CAST(?5 AS INTEGER),?3,?4,1)",
            &[id, &room, &token, payload, &epoch_text],
        )?;
        if changed != 1 {
            return Err("INSERT_NOT_ONE_ROW".into());
        }
        inject_sigkill("AFTER_INSERT_BEFORE_COMMIT");
        Ok("ACCEPTED")
    })();

    match result {
        Ok("ACCEPTED") => {
            db.exec("COMMIT")?;
            inject_sigkill("AFTER_COMMIT_BEFORE_ACK");
            Ok("ACCEPTED")
        }
        Ok(other) => {
            db.exec("ROLLBACK")?;
            Ok(other)
        }
        Err(e) => {
            let rollback = db.exec("ROLLBACK");
            if let Err(r) = rollback {
                return Err(format!("{e};ROLLBACK:{r}"));
            }
            Err(e)
        }
    }
}


#[derive(serde::Deserialize)]
#[serde(deny_unknown_fields)]
struct JsonToken {
    version: u64,
    room: String,
    id: String,
    limit: u64,
    epoch: u64,
    signature: String,
}

fn parse_json_token(bytes: &[u8]) -> Option<(JsonToken, Vec<u8>)> {
    use base64::Engine as _;

    if bytes.len() > 8192 {
        return None;
    }

    let token: JsonToken = serde_json::from_slice(bytes).ok()?;

    if token.version != 2
        || token.limit == 0
        || token.epoch == 0
        || token.limit > i64::MAX as u64
        || token.epoch > i64::MAX as u64
        || !valid_hex(&token.room, 64)
        || !valid_hex(&token.id, 32)
        || token.signature.len() != 86
    {
        return None;
    }

    let engine = base64::engine::general_purpose::URL_SAFE_NO_PAD;

    let signature = engine.decode(&token.signature).ok()?;
    if signature.len() != 64
        || engine.encode(&signature) != token.signature
    {
        return None;
    }

    Some((token, signature))
}

fn main() -> Result<(), String> {
    let args: Vec<String> = env::args().collect();

    if args.len() != 4 {
        return Err(
            "USAGE:worker DATABASE PUBLICATION_ID TOKEN_JSON_FILE".into()
        );
    }

    let publication = &args[2];

    if !valid_hex(publication, 32) {
        return Err("INVALID_PUBLICATION_ID".into());
    }

    let bytes = fs::read(&args[3])
        .map_err(|e| format!("TOKEN_READ_FAILED:{e}"))?;

    // Parse exactly once. Do not accept token claims from CLI.
    let Some((token, signature)) = parse_json_token(&bytes) else {
        println!("ADMISSION_RESULT=UNAUTHORIZED");
        return Ok(());
    };

    let db = Db::open(&args[1])?;
    db.exec("PRAGMA busy_timeout=10000")?;

    let result = admission(
        &db,
        publication,
        &token.room,
        &token.id,
        token.limit as i64,
        token.epoch as i64,
        &signature,
    )?;

    println!("ADMISSION_RESULT={result}");
    Ok(())
}

fn valid_hex(s: &str, n: usize) -> bool {
    s.len() == n && s.bytes().all(|b| {
        b.is_ascii_digit() || (b'a'..=b'f').contains(&b)
    })
}

mod crypto {
    use std::ffi::CString;
    use std::os::raw::{c_char, c_int, c_void};
    use std::ptr;

    #[repr(C)]
    struct Pkey { _private: [u8; 0] }
    #[repr(C)]
    struct MdCtx { _private: [u8; 0] }
    #[repr(C)]
    struct PkeyCtx { _private: [u8; 0] }

    #[link(name = "crypto")]
    unsafe extern "C" {
        fn EVP_PKEY_new_raw_public_key_ex(
            libctx: *mut c_void,
            keytype: *const c_char,
            propq: *const c_char,
            key: *const u8,
            keylen: usize,
        ) -> *mut Pkey;
        fn EVP_PKEY_free(key: *mut Pkey);
        fn EVP_MD_CTX_new() -> *mut MdCtx;
        fn EVP_MD_CTX_free(ctx: *mut MdCtx);
        fn EVP_DigestVerifyInit(
            ctx: *mut MdCtx,
            pctx: *mut *mut PkeyCtx,
            digest: *const c_void,
            engine: *mut c_void,
            key: *mut Pkey,
        ) -> c_int;
        fn EVP_DigestVerify(
            ctx: *mut MdCtx,
            sig: *const u8, siglen: usize,
            msg: *const u8, msglen: usize
        ) -> c_int;
    }

    struct Key(*mut Pkey);
    impl Drop for Key {
        fn drop(&mut self) {
            if !self.0.is_null() {
                unsafe { EVP_PKEY_free(self.0); }
            }
        }
    }
    struct Context(*mut MdCtx);
    impl Drop for Context {
        fn drop(&mut self) {
            if !self.0.is_null() {
                unsafe { EVP_MD_CTX_free(self.0); }
            }
        }
    }

    fn decode_base64url(value: &str) -> Option<Vec<u8>> {
        if value.is_empty() || value.len() % 4 == 1 {
            return None;
        }
        let mut result = Vec::new();
        let mut buffer: u32 = 0;
        let mut bits: u32 = 0;

        for b in value.bytes() {
            let n = match b {
                b'A'..=b'Z' => (b - b'A') as u32,
                b'a'..=b'z' => (b - b'a' + 26) as u32,
                b'0'..=b'9' => (b - b'0' + 52) as u32,
                b'-' => 62,
                b'_' => 63,
                _ => return None,
            };
            buffer = (buffer << 6) | n;
            bits += 6;
            if bits >= 8 {
                bits -= 8;
                result.push((buffer >> bits) as u8);
                buffer &= (1 << bits) - 1;
            }
        }
        if bits >= 6 || buffer != 0 {
            return None;
        }
        Some(result)
    }

    pub fn verify_claims(
        issuer_spki: &str,
        room: &str,
        token_id: &str,
        limit: i64,
        epoch: i64,
        signature: &[u8],
    ) -> Result<bool, String> {
        if signature.len() != 64 {
            return Ok(false);
        }
        let Some(der) = decode_base64url(issuer_spki) else {
            return Ok(false);
        };

        // Canonical DER/SPKI prefix for a 32-byte Ed25519 public key.
        let prefix: [u8; 12] = [
            0x30, 0x2a, 0x30, 0x05, 0x06, 0x03,
            0x2b, 0x65, 0x70, 0x03, 0x21, 0x00
        ];
        if der.len() != 44 || !der.starts_with(&prefix) {
            return Ok(false);
        }

        let algorithm = CString::new("ED25519").unwrap();
        let key = Key(unsafe {
            EVP_PKEY_new_raw_public_key_ex(
                ptr::null_mut(), algorithm.as_ptr(),
                ptr::null(), der[12..].as_ptr(), 32
            )
        });
        if key.0.is_null() {
            return Err("ED25519_PUBLIC_KEY_CREATE_FAILED".into());
        }

        let message = format!(
            r#"["kant-publish-v2","{}","{}",{},{}]"#,
            room, token_id, limit, epoch
        );
        let ctx = Context(unsafe { EVP_MD_CTX_new() });
        if ctx.0.is_null() {
            return Err("ED25519_CONTEXT_FAILED".into());
        }
        let rc = unsafe {
            EVP_DigestVerifyInit(
                ctx.0, ptr::null_mut(), ptr::null(),
                ptr::null_mut(), key.0
            )
        };
        if rc != 1 {
            return Err("ED25519_INIT_FAILED".into());
        }

        let rc = unsafe {
            EVP_DigestVerify(
                ctx.0,
                signature.as_ptr(), signature.len(),
                message.as_bytes().as_ptr(),
                message.len()
            )
        };
        match rc {
            1 => Ok(true),
            0 => Ok(false),
            _ => Err(format!("ED25519_VERIFY_ERROR:{rc}")),
        }
    }
}


// Experimental process-local crash hooks.
// Activated only when the test sets INT05_RUST_CRASH_POINT.
// Never incorporate these hooks into a production build.

unsafe extern "C" {
    fn kill(pid: i32, signal: i32) -> i32;
}

fn inject_sigkill(point: &str) {
    if std::env::var("INT05_RUST_CRASH_POINT")
        .ok()
        .as_deref() != Some(point)
    {
        return;
    }

    eprintln!("INT05_SIGKILL_POINT={point}");

    let pid = std::process::id() as i32;
    let result = unsafe { kill(pid, 9) };

    // Fail closed if signal delivery unexpectedly returns.
    eprintln!("SIGKILL_UNEXPECTED_RETURN={result}");
    std::process::abort();
}
