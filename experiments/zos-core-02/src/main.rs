mod sqlite;

use sqlite::{Db, Transaction};
use std::fs;
#[cfg(core02_test)]
use std::io;
use std::io::{Read, Write};
use std::path::Path;
use std::process::{Command, Stdio};

type Result<T> = std::result::Result<T, String>;
const DESCRIPTOR: &str = include_str!("../core01/evidence/descriptor.txt");
const KEY: &[u8] = include_bytes!(env!("CORE02_TRUSTED_KEY"));
const PREFIX: &str =
    "zos.core01b.receipt.v1\nverdict=accepted\nbasis=source-compiled-jobverifier-fixture\n";
const DOMAIN: &str = "zos.core01b.synthetic.v1";
const REQUEST: &str = "fixture-request-0001";
const OPERATION: &str = "treasury:debit:7";
const SCHEMA: &str = include_str!("001.sql");

fn read(path: &str, limit: usize) -> Result<Vec<u8>> {
    let mut bytes = Vec::new();
    fs::File::open(path)
        .and_then(|f| f.take(limit as u64 + 1).read_to_end(&mut bytes))
        .map_err(|e| format!("INPUT:{e}"))?;
    if bytes.len() > limit {
        return Err("INPUT_SIZE".into());
    }
    Ok(bytes)
}

fn hash(bytes: &[u8]) -> Result<String> {
    let mut child = Command::new("/usr/bin/sha256sum")
        .env_clear()
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .map_err(|e| e.to_string())?;
    let write = child.stdin.take().ok_or("HASH_PIPE")?.write_all(bytes);
    let out = child.wait_with_output().map_err(|e| e.to_string())?;
    write.map_err(|e| e.to_string())?;
    if !out.status.success() {
        return Err("HASH".into());
    }
    String::from_utf8(out.stdout.get(..64).ok_or("HASH")?.to_vec()).map_err(|e| e.to_string())
}

struct Scratch(std::path::PathBuf);
impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn authenticate(workspace: &Path, message: &[u8], signature: &[u8]) -> Result<()> {
    if signature.len() != 64 {
        return Err("SIGNATURE".into());
    }
    use std::os::unix::fs::DirBuilderExt;
    let path = workspace.join(format!("verify-{}", std::process::id()));
    fs::DirBuilder::new()
        .mode(0o700)
        .create(&path)
        .map_err(|e| format!("SCRATCH:{e}"))?;
    let dir = Scratch(path);
    for (name, data) in [
        ("key.pem", KEY),
        ("message", message),
        ("signature", signature),
    ] {
        fs::write(dir.0.join(name), data).map_err(|e| format!("SCRATCH:{e}"))?;
    }
    let out = Command::new("/usr/bin/openssl")
        .env_clear()
        .current_dir(&dir.0)
        .args([
            "pkeyutl",
            "-rawin",
            "-verify",
            "-pubin",
            "-inkey",
            "key.pem",
            "-in",
            "message",
            "-sigfile",
            "signature",
        ])
        .output()
        .map_err(|e| format!("SIGNATURE_PROCESS:{e}"))?;
    if !out.status.success() {
        return Err("SIGNATURE".into());
    }
    Ok(())
}

fn configure(db: &Db) -> Result<()> {
    db.exec("PRAGMA busy_timeout=750; PRAGMA synchronous=FULL; PRAGMA foreign_keys=ON; PRAGMA trusted_schema=OFF;")?;
    if db.query("PRAGMA synchronous", &[])?.0 != Some(2)
        || db.query("PRAGMA foreign_keys", &[])?.0 != Some(1)
    {
        return Err("SQLITE_CONFIGURATION".into());
    }
    Ok(())
}

fn check_schema(db: &Db) -> Result<()> {
    if db.query("PRAGMA user_version", &[])?.0 != Some(1)
        || db.query("PRAGMA application_id", &[])?.0 != Some(1515140146)
        || db
            .query(
                "SELECT count(*) FROM pragma_journal_mode WHERE journal_mode='delete'",
                &[],
            )?
            .0
            != Some(1)
        || db
            .query(
                "SELECT count(*) FROM sqlite_schema WHERE name NOT LIKE 'sqlite_autoindex_%'",
                &[],
            )?
            .0
            != Some(3)
    {
        return Err("SCHEMA".into());
    }
    for ddl in SCHEMA.trim_end().split(";\n") {
        let ddl = ddl.trim_end_matches(';');
        if db
            .query("SELECT count(*) FROM sqlite_schema WHERE sql=?1", &[ddl])?
            .0
            != Some(1)
        {
            return Err("SCHEMA".into());
        }
    }
    if db
        .query(
            "SELECT count(*) FROM pragma_quick_check WHERE quick_check <> 'ok'",
            &[],
        )?
        .0
        != Some(0)
        || db
            .query("SELECT count(*) FROM pragma_foreign_key_check", &[])?
            .0
            != Some(0)
    {
        return Err("DB_INTEGRITY".into());
    }
    Ok(())
}

fn init(path: &str) -> Result<()> {
    let db = Db::open(path, true)?;
    configure(&db)?;
    let tx = Transaction::begin(&db)?;
    if db.query("PRAGMA user_version", &[])?.0 == Some(0)
        && db.query("PRAGMA application_id", &[])?.0 == Some(0)
        && db.query("SELECT count(*) FROM sqlite_schema", &[])?.0 == Some(0)
    {
        db.exec(SCHEMA)?;
        db.exec("PRAGMA user_version=1; PRAGMA application_id=1515140146;")?;
    }
    check_schema(&db)?;
    tx.commit()
}

#[cfg(core02_test)]
fn checkpoint(mode: &str, point: &str) -> Result<()> {
    if mode == point {
        println!("CHECKPOINT {point}");
        io::stdout().flush().map_err(|e| e.to_string())?;
        loop {
            std::thread::park();
        }
    }
    Ok(())
}

fn consume(path: &str, args: &[String], _mode: &str) -> Result<&'static str> {
    let [message_path, signature_path, artifact_path, authority, operation] = args else {
        return Err("ARGUMENTS".into());
    };
    let message = read(message_path, 4096)?;
    let signature = read(signature_path, 64)?;
    authenticate(
        Path::new(path)
            .parent()
            .filter(|p| !p.as_os_str().is_empty())
            .unwrap_or(Path::new(".")),
        &message,
        &signature,
    )?;
    if authority != "treasury" {
        return Err("AUTHORITY".into());
    }
    if operation != OPERATION {
        return Err("OPERATION".into());
    }
    if message != format!("{PREFIX}{DESCRIPTOR}").as_bytes() {
        return Err("DESCRIPTOR".into());
    }
    let artifact_hash = hash(&read(artifact_path, 1_048_576)?)?;
    let expected = DESCRIPTOR
        .lines()
        .find_map(|s| s.strip_prefix("artifact-sha256="))
        .ok_or("PIN")?;
    if artifact_hash != expected {
        return Err("ARTIFACT".into());
    }
    let issuer = hash(KEY)?;
    let signature_hex: String = signature.iter().map(|b| format!("{b:02x}")).collect();
    let text = std::str::from_utf8(&message).map_err(|e| e.to_string())?;

    let db = Db::open(path, false)?;
    configure(&db)?;
    let tx = Transaction::begin(&db)?;
    check_schema(&db)?;
    if db
        .query(
            "SELECT count(*) FROM receipts WHERE domain=?1 AND request=?2",
            &[DOMAIN, REQUEST],
        )?
        .0
        == Some(1)
    {
        tx.rollback()?;
        return Ok("REPLAY");
    }
    if db
        .query("SELECT balance FROM treasury", &[])?
        .0
        .unwrap_or(-1)
        < 7
    {
        return Err("INSUFFICIENT".into());
    }
    let (_, changed) = db.query(
        "INSERT INTO receipts VALUES (?1,?2,?3,?4,?5,?6,?7,?8)",
        &[
            DOMAIN,
            REQUEST,
            text,
            &signature_hex,
            &artifact_hash,
            operation,
            &issuer,
            authority,
        ],
    )?;
    if changed != 1 {
        return Err("RECEIPT_WRITE_COUNT".into());
    }
    #[cfg(core02_test)]
    match _mode {
        "write-failure" => db.exec("PRAGMA query_only=ON")?,
        "rollback" => return Err("INJECTED_ROLLBACK".into()),
        _ => {}
    }
    let (_, changed) = db.query("INSERT INTO effects VALUES (?1,?2,-7)", &[DOMAIN, REQUEST])?;
    if changed != 1 {
        return Err("EFFECT_WRITE_COUNT".into());
    }
    #[cfg(core02_test)]
    checkpoint(_mode, "before-commit")?;
    tx.commit()?;
    #[cfg(core02_test)]
    checkpoint(_mode, "after-commit")?;
    Ok("APPLIED")
}

fn run(args: &[String]) -> Result<()> {
    match args {
        [action, db] if action == "init" => init(db),
        [action, db, rest @ ..] if action == "consume" => {
            println!("{}", consume(db, rest, "")?);
            Ok(())
        }
        #[cfg(core02_test)]
        [action, db, mode, rest @ ..] if action == "test" => {
            println!("{}", consume(db, rest, mode)?);
            if mode == "same-process" {
                println!("{}", consume(db, rest, "")?);
            }
            Ok(())
        }
        _ => Err("ARGUMENTS".into()),
    }
}

fn main() {
    if let Err(error) = run(&std::env::args().skip(1).collect::<Vec<_>>()) {
        eprintln!("DENIED {error}");
        std::process::exit(1);
    }
}
