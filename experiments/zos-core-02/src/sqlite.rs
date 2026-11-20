use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int, c_void};
use std::ptr;

#[repr(C)]
struct RawDb {
    _private: [u8; 0],
}
#[repr(C)]
struct RawStmt {
    _private: [u8; 0],
}

#[link(name = "sqlite3")]
unsafe extern "C" {
    fn sqlite3_open_v2(
        path: *const c_char,
        out: *mut *mut RawDb,
        flags: c_int,
        vfs: *const c_char,
    ) -> c_int;
    fn sqlite3_close(db: *mut RawDb) -> c_int;
    fn sqlite3_exec(
        db: *mut RawDb,
        sql: *const c_char,
        cb: Option<
            unsafe extern "C" fn(*mut c_void, c_int, *mut *mut c_char, *mut *mut c_char) -> c_int,
        >,
        arg: *mut c_void,
        err: *mut *mut c_char,
    ) -> c_int;
    fn sqlite3_free(ptr: *mut c_void);
    fn sqlite3_errmsg(db: *mut RawDb) -> *const c_char;
    fn sqlite3_prepare_v2(
        db: *mut RawDb,
        sql: *const c_char,
        n: c_int,
        out: *mut *mut RawStmt,
        tail: *mut *const c_char,
    ) -> c_int;
    fn sqlite3_bind_text(
        stmt: *mut RawStmt,
        index: c_int,
        value: *const c_char,
        n: c_int,
        destructor: Option<unsafe extern "C" fn(*mut c_void)>,
    ) -> c_int;
    fn sqlite3_step(stmt: *mut RawStmt) -> c_int;
    fn sqlite3_column_int64(stmt: *mut RawStmt, i: c_int) -> i64;
    fn sqlite3_finalize(stmt: *mut RawStmt) -> c_int;
    fn sqlite3_changes(db: *mut RawDb) -> c_int;
}

const OK: i32 = 0;
const ROW: i32 = 100;
const DONE: i32 = 101;

pub struct Db(*mut RawDb);
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
    pub fn open(path: &str, create: bool) -> Result<Self, String> {
        let path = CString::new(path).map_err(|e| e.to_string())?;
        let mut raw = ptr::null_mut();
        let rc = unsafe {
            sqlite3_open_v2(
                path.as_ptr(),
                &mut raw,
                if create { 6 } else { 2 },
                ptr::null(),
            )
        };
        if rc != OK || raw.is_null() {
            if !raw.is_null() {
                unsafe {
                    sqlite3_close(raw);
                }
            }
            return Err(format!("OPEN:{rc}"));
        }
        Ok(Self(raw))
    }

    fn error(&self, label: &str, rc: i32) -> String {
        let message = unsafe {
            CStr::from_ptr(sqlite3_errmsg(self.0))
                .to_string_lossy()
                .into_owned()
        };
        format!("{label}:{rc}:{message}")
    }

    pub fn exec(&self, sql: &str) -> Result<(), String> {
        let sql = CString::new(sql).map_err(|e| e.to_string())?;
        let mut msg = ptr::null_mut();
        let rc = unsafe { sqlite3_exec(self.0, sql.as_ptr(), None, ptr::null_mut(), &mut msg) };
        let details = if msg.is_null() {
            String::new()
        } else {
            let s = unsafe { CStr::from_ptr(msg).to_string_lossy().into_owned() };
            unsafe {
                sqlite3_free(msg.cast());
            }
            s
        };
        if rc != OK {
            return Err(format!("EXEC:{rc}:{details}"));
        }
        Ok(())
    }

    pub fn query(&self, sql: &str, params: &[&str]) -> Result<(Option<i64>, i32), String> {
        let sql = CString::new(sql).map_err(|e| e.to_string())?;
        let mut raw = ptr::null_mut();
        let owned: Vec<CString> = params
            .iter()
            .map(|p| CString::new(*p).map_err(|e| e.to_string()))
            .collect::<Result<_, _>>()?;
        let rc = unsafe { sqlite3_prepare_v2(self.0, sql.as_ptr(), -1, &mut raw, ptr::null_mut()) };
        if rc != OK {
            return Err(self.error("PREPARE", rc));
        }
        if raw.is_null() {
            return Err("EMPTY_STATEMENT".into());
        }
        let stmt = Stmt(raw);

        for (i, value) in owned.iter().enumerate() {
            let n = i32::try_from(value.as_bytes().len()).map_err(|e| e.to_string())?;
            let rc = unsafe {
                sqlite3_bind_text(
                    stmt.0,
                    i32::try_from(i + 1).map_err(|e| e.to_string())?,
                    value.as_ptr(),
                    n,
                    None,
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
pub struct Transaction<'a> {
    db: &'a Db,
    active: bool,
}

impl<'a> Transaction<'a> {
    pub fn begin(db: &'a Db) -> Result<Self, String> {
        db.exec("BEGIN IMMEDIATE")?;

        Ok(Self { db, active: true })
    }

    pub fn rollback(mut self) -> Result<(), String> {
        self.db.exec("ROLLBACK")?;
        self.active = false;
        Ok(())
    }

    pub fn commit(mut self) -> Result<(), String> {
        self.db.exec("COMMIT")?;
        self.active = false;
        Ok(())
    }
}

impl Drop for Transaction<'_> {
    fn drop(&mut self) {
        if self.active {
            let _ = self.db.exec("ROLLBACK");
        }
    }
}
