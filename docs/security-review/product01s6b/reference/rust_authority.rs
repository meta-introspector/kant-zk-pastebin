use std::env;
use std::ffi::{c_char,c_int,c_void,CStr,CString};
use std::ptr;

unsafe extern "C" {
    fn sqlite3_open_v2(
        path:*const c_char,db:*mut *mut c_void,
        flags:c_int,vfs:*const c_char
    )->c_int;
    fn sqlite3_close(db:*mut c_void)->c_int;
    fn sqlite3_close_v2(db:*mut c_void)->c_int;
    fn sqlite3_busy_timeout(db:*mut c_void,ms:c_int)->c_int;
    fn sqlite3_prepare_v2(
        db:*mut c_void,sql:*const c_char,
        len:c_int,stmt:*mut *mut c_void,
        tail:*mut *const c_char
    )->c_int;
    fn sqlite3_bind_text(
        stmt:*mut c_void,index:c_int,
        value:*const c_char,len:c_int,
        destructor:Option<unsafe extern "C" fn(*mut c_void)>
    )->c_int;
    fn sqlite3_step(stmt:*mut c_void)->c_int;
    fn sqlite3_finalize(stmt:*mut c_void)->c_int;
    fn sqlite3_column_count(stmt:*mut c_void)->c_int;
    fn sqlite3_column_text(
        stmt:*mut c_void,index:c_int
    )->*const u8;
    fn sqlite3_errmsg(db:*mut c_void)->*const c_char;
    fn sqlite3_changes(db:*mut c_void)->c_int;
}


unsafe extern "C" {
    fn EVP_sha256()->*const c_void;
    fn HMAC(
        md:*const c_void,
        key:*const c_void,
        key_len:c_int,
        data:*const u8,
        data_len:usize,
        output:*mut u8,
        output_len:*mut u32
    )->*mut u8;
}

fn receipt_for(id:&str,rid:&str,tag:&str)
    ->Result<String,String>
{
    let key_path=env::var("P11C_KEY")
        .map_err(|_|"MISSING_KEY_PATH".to_string())?;
    let key=std::fs::read(key_path)
        .map_err(|_|"KEY_READ_DENY".to_string())?;
    if key.len()!=32 {
        return Err("KEY_LENGTH_DENY".into());
    }

    let mut msg=b"ZOS-AUTH-COMMIT-V1\x00".to_vec();
    for field in [id,rid,tag] {
        let bytes=field.as_bytes();
        let len=u32::try_from(bytes.len())
            .map_err(|_|"FIELD_TOO_LONG".to_string())?;
        msg.extend_from_slice(&len.to_be_bytes());
        msg.extend_from_slice(bytes);
    }

    let mut digest=[0u8;32];
    let mut digest_len=0u32;
    let result=unsafe {
        HMAC(
            EVP_sha256(),
            key.as_ptr() as *const c_void,
            32,
            msg.as_ptr(),
            msg.len(),
            digest.as_mut_ptr(),
            &mut digest_len
        )
    };
    if result.is_null() || digest_len!=32 {
        return Err("HMAC_DENY".into());
    }

    let mut out=String::with_capacity(64);
    for byte in digest {
        use std::fmt::Write;
        write!(&mut out,"{byte:02x}")
            .map_err(|_|"ENCODING_DENY".to_string())?;
    }
    Ok(out)
}


unsafe extern "C" {
    fn CRYPTO_memcmp(
        a:*const c_void,
        b:*const c_void,
        length:usize,
    )->c_int;
}

fn receipt_equal(a:&str,b:&str)->bool {
    if a.len()!=64 || b.len()!=64 {
        return false;
    }
    unsafe {
        CRYPTO_memcmp(
            a.as_ptr() as *const c_void,
            b.as_ptr() as *const c_void,
            64
        )==0
    }
}


// SQLite's SQLITE_TRANSIENT destructor sentinel (-1).
// SQLite copies the parameter before sqlite3_bind_text
// returns; the Rust CString need not outlive the statement.
fn sqlite_transient()
    ->unsafe extern "C" fn(*mut c_void)
{
    unsafe {
        std::mem::transmute::<
            isize,
            unsafe extern "C" fn(*mut c_void)
        >(-1isize)
    }
}

const SQLITE_ROW:i32=100;
const SQLITE_DONE:i32=101;

struct Db(*mut c_void);

impl Db {
    fn close_checked(&mut self)->Result<(),String> {
        if self.0.is_null() {
            return Ok(());
        }

        let rc=unsafe {sqlite3_close(self.0)};

        if rc!=0 {
            // sqlite3_close returns SQLITE_BUSY if
            // statements or other objects remain live.
            // The handle remains valid for a retry.
            return Err(format!(
                "SQLITE_CLOSE_FAILED={rc}"
            ));
        }

        self.0=ptr::null_mut();
        Ok(())
    }
}

impl Drop for Db {
    fn drop(&mut self) {
        if !self.0.is_null() {
            // Fallback for error paths. close_v2 safely
            // defers destruction while statements remain.
            // This does not replace explicit close checks.
            let rc=unsafe {sqlite3_close_v2(self.0)};
            if rc!=0 {
                eprintln!("SQLITE_CLOSE_V2_FAILED={rc}");
            }
            self.0=ptr::null_mut();
        }
    }
}
struct Statement(*mut c_void);

fn finish_with_error(
    stmt:Statement,
    original:String,
)->String {
    match stmt.finish() {
        Ok(())=>original,
        Err(finalize_error)=>format!(
            "{original}; {finalize_error}"
        ),
    }
}
impl Statement {
    fn finish(mut self)->Result<(),String> {
        let handle=std::mem::replace(
            &mut self.0,
            ptr::null_mut()
        );
        if handle.is_null() {
            return Err("FINALIZE_NULL_HANDLE".into());
        }
        let rc=unsafe { sqlite3_finalize(handle) };
        if rc!=0 {
            return Err(format!(
                "SQLITE_FINALIZE_FAILED={rc}"
            ));
        }
        Ok(())
    }
}

impl Drop for Statement {
    fn drop(&mut self) {
        if !self.0.is_null() {
            unsafe {sqlite3_finalize(self.0);}
        }
    }
}
impl Db {
    fn error(&self)->String {
        unsafe {
            CStr::from_ptr(sqlite3_errmsg(self.0))
                .to_string_lossy().into_owned()
        }
    }
    fn open(path:&str)->Result<Self,String> {
        let filename=CString::new(path)
            .map_err(|_|"INVALID_PATH")?;
        let mut raw=ptr::null_mut();
        let rc=unsafe {
            sqlite3_open_v2(
                filename.as_ptr(),&mut raw,
                2|0x10000,ptr::null()
            )
        };
        if rc!=0 || raw.is_null() {
            if !raw.is_null() {
                unsafe {sqlite3_close(raw);}
            }
            return Err("OPEN_DENY".into());
        }
        let db=Self(raw);
        if unsafe {sqlite3_busy_timeout(db.0,15000)}!=0 {
            return Err("TIMEOUT_DENY".into());
        }
        Ok(db)
    }
    fn sql(
        &self,text:&str,params:&[&str]
    )->Result<Vec<Vec<String>>,String> {
        let sql=CString::new(text)
            .map_err(|_|"SQL_NUL")?;
        let mut raw=ptr::null_mut();
        let mut tail: *const c_char=ptr::null();
        let rc=unsafe {
            sqlite3_prepare_v2(
                self.0,sql.as_ptr(),-1,
                &mut raw,&mut tail
            )
        };
        if rc!=0 || raw.is_null() {
            let original=format!(
                "PREPARE:{}",self.error()
            );
            if !raw.is_null() {
                return Err(finish_with_error(
                    Statement(raw),original
                ));
            }
            return Err(original);
        }
        // Fail closed on trailing SQL or unexpected NULL tail.
        if tail.is_null() {
            return Err(finish_with_error(
                Statement(raw),
                "SQL_TAIL_UNAVAILABLE".into()
            ));
        }
        let trailing=unsafe {
            CStr::from_ptr(tail).to_bytes()
        };
        if !trailing.iter().all(|c|c.is_ascii_whitespace()) {
            return Err(finish_with_error(
                Statement(raw),
                "SQL_TRAILING_DENY".into()
            ));
        }

        let stmt=Statement(raw);
        // Keep all bound C strings alive until finalize.
        let values:Vec<CString>=params.iter()
            .map(|v|CString::new(*v))
            .collect::<Result<_,_>>()
            .map_err(|_|"PARAM_NUL")?;
        for (index,value) in values.iter().enumerate() {
            let rc=unsafe {
                sqlite3_bind_text(
                    stmt.0,(index+1) as i32,
                    value.as_ptr(),-1,Some(sqlite_transient())
                )
            };
            if rc!=0 {
                let original=format!(
                    "BIND:{}",self.error()
                );
                return Err(finish_with_error(
                    stmt,original
                ));
            }
        }
        let mut result=Vec::new();
        loop {
            let rc=unsafe {sqlite3_step(stmt.0)};
            if rc==SQLITE_DONE {break;}
            if rc!=SQLITE_ROW {
                let original=format!(
                    "STEP:{}",self.error()
                );
                return Err(finish_with_error(
                    stmt,original
                ));
            }
            let count=unsafe {sqlite3_column_count(stmt.0)};
            let mut row=Vec::new();
            for i in 0..count {
                let p=unsafe {sqlite3_column_text(stmt.0,i)};
                if p.is_null() {
                    return Err(finish_with_error(
                        stmt,
                        "UNEXPECTED_NULL".into()
                    ));
                }
                row.push(unsafe {
                    CStr::from_ptr(p as *const c_char)
                        .to_string_lossy().into_owned()
                });
            }
            result.push(row);
        }
        stmt.finish()?;
        Ok(result)
    }
    fn changes(&self)->i32 {
        unsafe {sqlite3_changes(self.0)}
    }
}

fn valid_hex(value:&str,len:usize)->bool {
    value.len()==len &&
    value.bytes().all(|c|c.is_ascii_hexdigit()
        && !c.is_ascii_uppercase())
}
fn valid_rid(value:&str)->bool {
    !value.is_empty() && value.len()<=64 &&
    value.bytes().all(|c|
        c.is_ascii_alphanumeric()||c==b'_'||c==b'-')
}

fn operation(
    db:&Db,mode:&str,id:&str,rid:&str,tag:&str,receipt:&str
)->Result<&'static str,String> {
    let claim=db.sql(
        "SELECT tag,state FROM claims WHERE dbid=? AND rid=?",
        &[id,rid]
    )?;
    let records=db.sql(
        "SELECT tag,receipt FROM commits WHERE dbid=? AND rid=?",
        &[id,rid]
    )?;
    if claim.len()>1 || records.len()>1 {
        return Ok("STATE_MISMATCH_DENY");
    }
    let c=claim.first();
    let r=records.first();

    if mode=="reserve" {
        return match c {
            None => {
                if r.is_some() {
                    Ok("ORPHAN_COMMIT_DENY")
                } else {
                    db.sql(
                        "INSERT INTO claims(dbid,rid,tag,state) \
                         VALUES(?,?,?,'CLAIMED')",
                        &[id,rid,tag]
                    )?;
                    Ok("RESERVED")
                }
            }
            Some(row) => {
                if row[0]!=tag {
                    Ok("CONFLICT_DENY")
                } else if row[1]=="CLAIMED" && r.is_none() {
                    Ok("RESERVATION_EXISTS")
                } else if row[1]=="COMMITTED" &&
                    r.is_some_and(|x|x[0]==tag && receipt_equal(&x[1],receipt)) {
                    Ok("REPLAY")
                } else {
                    Ok("STATE_MISMATCH_DENY")
                }
            }
        };
    }
    if mode!="commit" {
        return Ok("INVALID_MODE_DENY");
    }
    let Some(row)=c else {
        return Ok("UNRESERVED_DENY");
    };
    if row[0]!=tag {
        return Ok("CONFLICT_DENY");
    }
    if row[1]=="COMMITTED" {
        return match r {
            None => Ok("STALE_CANONICAL_DENY"),
            Some(x) if x[0]==tag && receipt_equal(&x[1],receipt) => Ok("REPLAY"),
            _ => Ok("INTEGRITY_DENY")
        };
    }
    if row[1]!="CLAIMED" || r.is_some() {
        return Ok("STATE_MISMATCH_DENY");
    }
    db.sql(
        "INSERT INTO commits(dbid,rid,tag,receipt) VALUES(?,?,?,?)",
        &[id,rid,tag,receipt]
    )?;
    db.sql(
        "UPDATE claims SET state='COMMITTED' \
         WHERE dbid=? AND rid=? AND tag=? AND state='CLAIMED'",
        &[id,rid,tag]
    )?;
    if db.changes()!=1 {
        return Err("CLAIM_UPDATE_FAILED".into());
    }
    Ok("COMMITTED")
}

fn run()->Result<&'static str,String> {
    let a:Vec<String>=env::args().collect();
    if a.len()!=6 {
        return Err("USAGE_DENY".into());
    }
    let (path,mode,id,rid,tag)=(
        &a[1],a[2].as_str(),a[3].as_str(),
        a[4].as_str(),a[5].as_str()
    );
    if !valid_hex(id,32) || !valid_rid(rid) ||
        !valid_hex(tag,64) {
        return Err("INVALID_INPUT".into());
    }
    let mut db=Db::open(path)?;
    db.sql("PRAGMA synchronous=FULL",&[])?;
    let receipt=receipt_for(id,rid,tag)?;
    db.sql("BEGIN IMMEDIATE",&[])?;
    let result=operation(&db,mode,id,rid,tag,&receipt);
    match result {
        Ok(status)=>{
            if let Err(error)=db.sql("COMMIT",&[]) {
                let _=db.sql("ROLLBACK",&[]);
                return Err(error);
            }
            db.close_checked()?;
            Ok(status)
        }
        Err(error)=>{
            let _=db.sql("ROLLBACK",&[]);
            Err(error)
        }
    }
}
fn main() {
    match run() {
        Ok(status)=>println!("{status}"),
        Err(error)=>{
            eprintln!("RUST_AUTHORITY_ERROR={error}");
            println!("AUTHORITY_DENY");
            std::process::exit(3);
        }
    }
}

#[cfg(test)]
mod p11f_tests {
    use super::*;

    #[test]
    fn rejects_second_sql_statement() {
        let db=Db::open(":memory:").unwrap();
        let e=db.sql("SELECT 1; SELECT 2",&[])
            .unwrap_err();
        assert_eq!(e,"SQL_TRAILING_DENY");
    }

    #[test]
    fn rejects_trailing_sql_comment() {
        let db=Db::open(":memory:").unwrap();
        let e=db.sql("SELECT 1; --extra",&[])
            .unwrap_err();
        assert_eq!(e,"SQL_TRAILING_DENY");
    }

    #[test]
    fn single_statement_and_binding_work() {
        let db=Db::open(":memory:").unwrap();
        let rows=db.sql("SELECT ?; \n",&["safe"]).unwrap();
        assert_eq!(rows,vec![vec!["safe".to_string()]]);
    }

    #[test]
    fn receipt_comparison_contract() {
        let a="a".repeat(64);
        let b="b".repeat(64);
        assert!(receipt_equal(&a,&a));
        assert!(!receipt_equal(&a,&b));
        assert!(!receipt_equal(&a,&"a".repeat(63)));
    }
}

#[cfg(test)]
mod p11g_tests {
    use super::*;

    #[test]
    fn transient_binding_copies_buffer() {
        let db=Db::open(":memory:").unwrap();
        let sql=CString::new("SELECT ?").unwrap();
        let mut raw=ptr::null_mut();

        let rc=unsafe {
            sqlite3_prepare_v2(
                db.0,
                sql.as_ptr(),
                -1,
                &mut raw,
                ptr::null_mut()
            )
        };
        assert_eq!(rc,0);
        assert!(!raw.is_null());

        let stmt=Statement(raw);

        let mut original=b"safe\0".to_vec();

        let rc=unsafe {
            sqlite3_bind_text(
                stmt.0,
                1,
                original.as_ptr() as *const c_char,
                4,
                Some(sqlite_transient())
            )
        };
        assert_eq!(rc,0);

        // The original buffer is overwritten after binding.
        original[..4].copy_from_slice(b"evil");

        assert_eq!(
            unsafe {sqlite3_step(stmt.0)},
            SQLITE_ROW
        );

        let result=unsafe {
            CStr::from_ptr(
                sqlite3_column_text(stmt.0,0)
                    as *const c_char
            ).to_str().unwrap().to_string()
        };

        assert_eq!(result,"safe");
        assert_eq!(
            unsafe {sqlite3_step(stmt.0)},
            SQLITE_DONE
        );
        assert!(stmt.finish().is_ok());
    }

    #[test]
    fn explicit_finalize_success() {
        let db=Db::open(":memory:").unwrap();
        let rows=db.sql("SELECT ?",&["verified"]).unwrap();
        assert_eq!(
            rows,
            vec![vec!["verified".to_string()]]
        );
    }

    #[test]
    fn transient_multi_parameter_roundtrip() {
        let db=Db::open(":memory:").unwrap();
        let rows=db.sql(
            "SELECT ?, ?, ?",
            &["alpha","beta","gamma"]
        ).unwrap();
        assert_eq!(
            rows,
            vec![vec![
                "alpha".to_string(),
                "beta".to_string(),
                "gamma".to_string()
            ]]
        );
    }
}

#[cfg(test)]
mod p11h_tests {
    use super::*;

    #[test]
    fn busy_close_then_finalize_and_retry() {
        let mut db=Db::open(":memory:").unwrap();

        let query=CString::new("SELECT 1").unwrap();
        let mut raw=ptr::null_mut();

        let rc=unsafe {
            sqlite3_prepare_v2(
                db.0,
                query.as_ptr(),
                -1,
                &mut raw,
                ptr::null_mut()
            )
        };
        assert_eq!(rc,0);
        assert!(!raw.is_null());

        let stmt=Statement(raw);

        // The active statement must prevent close.
        let error=db.close_checked().unwrap_err();
        assert_eq!(error,"SQLITE_CLOSE_FAILED=5");
        assert!(!db.0.is_null());

        // Finalize first, then close again.
        stmt.finish().unwrap();
        db.close_checked().unwrap();
        assert!(db.0.is_null());

        // Safe repeated close is an explicit no-op.
        db.close_checked().unwrap();
    }

    #[test]
    fn finalize_after_successful_query() {
        let mut db=Db::open(":memory:").unwrap();

        let rows=db.sql(
            "SELECT ?, ?",
            &["first","second"]
        ).unwrap();

        assert_eq!(
            rows,
            vec![vec![
                "first".to_string(),
                "second".to_string()
            ]]
        );

        db.close_checked().unwrap();
        assert!(db.0.is_null());
    }

    #[test]
    fn step_error_allows_fallback_cleanup() {
        let mut db=Db::open(":memory:").unwrap();

        db.sql(
            "CREATE TABLE t(id TEXT PRIMARY KEY)",
            &[]
        ).unwrap();

        db.sql(
            "INSERT INTO t VALUES(?)",
            &["duplicate"]
        ).unwrap();

        let error=db.sql(
            "INSERT INTO t VALUES(?)",
            &["duplicate"]
        );

        assert!(error.is_err());

        // The Statement Drop runs on the error path.
        // It must release the prepared statement so
        // close_checked can succeed.
        db.close_checked().unwrap();
        assert!(db.0.is_null());
    }
}

#[cfg(test)]
mod p11i_tests {
    use super::*;

    #[test]
    fn duplicate_step_error_preserves_finalization() {
        let mut db=Db::open(":memory:").unwrap();

        db.sql(
            "CREATE TABLE t(id TEXT PRIMARY KEY)",
            &[]
        ).unwrap();

        db.sql(
            "INSERT INTO t VALUES(?)",
            &["duplicate"]
        ).unwrap();

        let error=db.sql(
            "INSERT INTO t VALUES(?)",
            &["duplicate"]
        ).unwrap_err();

        assert!(error.contains("STEP:"),"{error}");

        // SQLite may report the last step error again
        // when finalizing the failed statement.
        // It must not be silently discarded.
        assert!(
            error.contains("SQLITE_FINALIZE_FAILED="),
            "{error}"
        );

        db.close_checked().unwrap();
    }

    #[test]
    fn invalid_parameter_releases_statement() {
        let mut db=Db::open(":memory:").unwrap();

        let error=db.sql(
            "SELECT ?",
            &["bad\0value"]
        ).unwrap_err();

        assert_eq!(error,"PARAM_NUL");
        db.close_checked().unwrap();
    }

    #[test]
    fn rejected_sql_tail_releases_statement() {
        let mut db=Db::open(":memory:").unwrap();

        let error=db.sql(
            "SELECT 1; SELECT 2",
            &[]
        ).unwrap_err();

        assert_eq!(error,"SQL_TRAILING_DENY");
        db.close_checked().unwrap();
    }

    #[test]
    fn failed_check_constraint_preserves_state() {
        let mut db=Db::open(":memory:").unwrap();

        db.sql(
            "CREATE TABLE t(x INTEGER CHECK(x>0))",
            &[]
        ).unwrap();

        let error=db.sql(
            "INSERT INTO t VALUES(-1)",
            &[]
        ).unwrap_err();

        assert!(error.contains("STEP:"),"{error}");

        let rows=db.sql(
            "SELECT COUNT(*) FROM t",
            &[]
        ).unwrap();

        assert_eq!(
            rows,
            vec![vec!["0".to_string()]]
        );

        db.close_checked().unwrap();
    }
}
