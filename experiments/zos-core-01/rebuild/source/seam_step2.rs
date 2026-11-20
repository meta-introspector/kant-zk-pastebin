use std::{env, fs, path::Path, process::{Command, Output, Stdio}};

fn lean() -> &'static str {
    static CONFIGURED_LEAN: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    CONFIGURED_LEAN.get_or_init(|| env::var("CORE_LEAN").expect("CORE_LEAN must name the configured Lean executable"))
}
const VERSION: &str = "Lean (version 4.35.0, x86_64-unknown-linux-gnu, commit eb6cafb7290e8bd5f2937522d8d804f58f02bafc, Release)\n";
const PIN: &str = "zos.core01b.descriptor.v1\njob=fixture-true-v1\ncommit=221cf074aaa3146f41863532a4fd9478dcba044f\ntoolchain=lean-4.35.0-eb6cafb7290e8bd5f2937522d8d804f58f02bafc\nmodule=Good\ntarget=target\nreference=Ref.expected\nproposition=True\npolicy=empty-axioms\nreplay-domain=zos.core01b.synthetic.v1\nrequest=fixture-request-0001\noperation=treasury:debit:7\n";
const INPUTS: [(&str, &str); 5] = [
    ("checker-sha256", "Check.lean"), ("source-sha256", "Good.lean"),
    ("reference-source-sha256", "Ref.lean"), ("artifact-sha256", "Good.olean"),
    ("reference-artifact-sha256", "Ref.olean"),
];

#[derive(Debug, PartialEq, Eq)]
enum Denial { Io, Process, Indeterminate, InvalidProof, Sorry, Mismatch, Descriptor, Artifact, Signature, Authorization, Operation, Replay }
type Result<T> = std::result::Result<T, Denial>;
impl From<std::io::Error> for Denial {
    fn from(_: std::io::Error) -> Self { Self::Io }
}

fn execute(dir: &Path, program: &str, args: &[&str]) -> Result<Output> {
    Command::new("/usr/bin/timeout").args(["-k", "2s", "30s", program]).args(args)
        .env_clear().env("PATH", env::var_os("PATH").expect("launcher PATH")).env("LC_ALL", "C").env("HOME", dir).env("TMPDIR", dir)
        .env("LEAN_PATH", dir).current_dir(dir).stdin(Stdio::null())
        .output().map_err(|_| Denial::Process)
}

fn hash(dir: &Path, file: &str) -> Result<String> {
    let out = execute(dir, "/usr/bin/sha256sum", &["--", file])?;
    let value = out.stdout.get(..64).ok_or(Denial::Io)?;
    if !out.status.success() || !value.iter().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(b)) {
        return Err(Denial::Io);
    }
    String::from_utf8(value.to_vec()).map_err(|_| Denial::Io)
}

fn descriptor(dir: &Path) -> Result<String> {
    let mut wire = PIN.to_owned();
    for (field, file) in INPUTS {
        wire.push_str(&format!("{field}={}\n", hash(dir, file)?));
    }
    wire.push_str(&format!("lean-binary-sha256={}\n", hash(dir, lean())?));
    Ok(wire)
}

fn observe(label: &str, output: &Output) {
    println!("{label} exit={:?} stdout={:?} stderr={:?}", output.status.code(),
        String::from_utf8_lossy(&output.stdout), String::from_utf8_lossy(&output.stderr));
}

fn check(dir: &Path, lean: &str, module: &str, expected: &str) -> Result<()> {
    let out = execute(dir, lean, &["--run", "Check.lean", "--module", module,
        "--decl", "target", "--ref", "Ref", "--expected", expected])?;
    observe("VERIFIER", &out);
    let exact = |reason: &str, axioms: &str| {
        let json = format!("{{\"axioms\":{axioms},\"decl\":\"target\",\"declaredAxiomsInSubmission\":[],\"jobModule\":\"{module}\",\"reasonCode\":\"{reason}\",\"schema\":\"zos.verify.v1-testonly\"}}\n");
        out.stderr.is_empty() && out.stdout == json.as_bytes()
    };
    match out.status.code() {
        Some(0) if exact("OK", "[]") => Ok(()),
        Some(1) if exact("SORRY", "[\"sorryAx\"]") => Err(Denial::Sorry),
        Some(1) if exact("STATEMENT_MISMATCH", "[]") => Err(Denial::Mismatch),
        Some(0..=2) => Err(Denial::Indeterminate),
        _ => Err(Denial::Process),
    }
}

#[derive(Clone)]
struct Receipt { message: Vec<u8>, signature: Vec<u8> }
fn message(desc: &str) -> Vec<u8> {
    format!("zos.core01b.receipt.v1\nverdict=accepted\nbasis=source-compiled-jobverifier-fixture\n{desc}").into_bytes()
}

fn sign(dir: &Path, desc: &str) -> Result<Receipt> {
    let message = message(desc);
    fs::write(dir.join("message.bin"), &message)?;
    let out = execute(dir, "/usr/bin/openssl", &["pkeyutl", "-rawin", "-sign",
        "-inkey", "issuer-key.pem", "-in", "message.bin", "-out", "signature.bin"])?;
    if !out.status.success() { return Err(Denial::Signature); }
    let signature = fs::read(dir.join("signature.bin"))?;
    if signature.len() != 64 { return Err(Denial::Signature); }
    Ok(Receipt { message, signature })
}

fn authenticate(dir: &Path, pinned_key: &[u8], receipt: &Receipt) -> Result<()> {
    if receipt.signature.len() != 64 { return Err(Denial::Signature); }
    fs::write(dir.join("verify-key.pem"), pinned_key)?;
    fs::write(dir.join("message.bin"), &receipt.message)?;
    fs::write(dir.join("signature.bin"), &receipt.signature)?;
    let out = execute(dir, "/usr/bin/openssl", &["pkeyutl", "-rawin", "-verify",
        "-pubin", "-inkey", "verify-key.pem", "-in", "message.bin", "-sigfile", "signature.bin"])?;
    if !out.status.success() { return Err(Denial::Signature); }
    Ok(())
}

struct Adapter<'a> { dir: &'a Path, pin: &'a str }
impl Adapter<'_> {
    fn issue(&self, request: &str) -> Result<Receipt> {
        if self.pin != request { return Err(Denial::Descriptor); }
        if descriptor(self.dir)? != self.pin { return Err(Denial::Artifact); }
        let out = execute(self.dir, lean(), &["--version"])?;
        if !out.status.success() || out.stdout != VERSION.as_bytes() || !out.stderr.is_empty() {
            return Err(Denial::Indeterminate);
        }
        self.after_check(|| check(self.dir, lean(), "Good", "expected"))
    }

    fn after_check(&self, verify: impl FnOnce() -> Result<()>) -> Result<Receipt> {
        verify()?;
        if descriptor(self.dir)? != self.pin { return Err(Denial::Artifact); }
        sign(self.dir, self.pin)
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct State { balance: u64, consumed: bool, replay_count: u64, audit_log: Vec<&'static str> }

struct Dao<'a> { dir: &'a Path, pin: &'a str, key: Vec<u8>, state: State }
impl Dao<'_> {
    fn apply(&mut self, operation: &'static str, artifact: &str, receipt: &Receipt) -> Result<()> {
        authenticate(self.dir, &self.key, receipt)?;
        let debit = match operation {
            "treasury:debit:7" => 7,
            "treasury:debit:8" => 8,
            _ => return Err(Denial::Authorization),
        };
        let expected = self.pin.replacen("operation=treasury:debit:7\n",
            &format!("operation={operation}\n"), 1);
        if receipt.message != message(&expected) { return Err(Denial::Operation); }
        let expected_hash = self.pin.lines().find_map(|line| line.strip_prefix("artifact-sha256="))
            .ok_or(Denial::Descriptor)?;
        if hash(self.dir, artifact)? != expected_hash { return Err(Denial::Artifact); }
        if self.state.consumed { return Err(Denial::Replay); }
        let balance = self.state.balance.checked_sub(debit).ok_or(Denial::Authorization)?;
        self.state.balance = balance;
        self.state.consumed = true;
        self.state.replay_count += 1;
        self.state.audit_log.push(operation);
        Ok(())
    }
}

fn reject(dao: &mut Dao, case: &str, expected: Denial, test: impl FnOnce(&mut Dao) -> Result<()>) {
    let before = dao.state.clone();
    assert_eq!(test(dao), Err(expected));
    assert_eq!(dao.state, before);
    println!("PASS {case} complete_state_unchanged=true");
}

fn run(dir: &Path) -> Result<()> {
    const DEBIT: &str = "treasury:debit:7";
    const ARTIFACT: &str = "Good.olean";
    let pin = fs::read_to_string(dir.join("descriptor.txt"))?;
    let adapter = Adapter { dir, pin: &pin };
    let mut dao = Dao { dir, pin: &pin, key: fs::read(dir.join("trusted-public.pem"))?,
        state: State { balance: 100, consumed: false, replay_count: 0, audit_log: vec![] } };
    let receipt = adapter.issue(&pin)?;
    let gated = |module, expected| adapter.after_check(|| check(dir, lean(), module, expected)).map(drop);

    reject(&mut dao, "02-invalid", Denial::InvalidProof, |_| adapter.after_check(|| {
        let out = execute(dir, lean(), &["Invalid.lean"])?;
        observe("COMPILER", &out);
        if out.status.code() == Some(1) && String::from_utf8_lossy(&out.stdout).contains("unsolved goals") {
            Err(Denial::InvalidProof)
        } else { Err(Denial::Indeterminate) }
    }).map(drop));
    reject(&mut dao, "03-sorry", Denial::Sorry, |_| gated("SorryCase", "expected"));
    fs::write(dir.join("wrong.olean"), b"wrong bytes")?;
    reject(&mut dao, "04-artifact", Denial::Artifact, |d| d.apply(DEBIT, "wrong.olean", &receipt));
    reject(&mut dao, "05-descriptor", Denial::Descriptor, |_| {
        adapter.issue(&pin.replace("proposition=True", "proposition=False")).map(drop)
    });
    let mut tampered = receipt.clone();
    tampered.message[0] ^= 1;
    reject(&mut dao, "06-tampered", Denial::Signature, |d| d.apply(DEBIT, ARTIFACT, &tampered));
    let mut wrong_key = Dao { dir, pin: &pin, key: fs::read(dir.join("other-public.pem"))?,
        state: dao.state.clone() };
    reject(&mut wrong_key, "07-wrong-key", Denial::Signature, |d| d.apply(DEBIT, ARTIFACT, &receipt));
    let mint = "treasury:mint:7";
    let forbidden = sign(dir, &pin.replace(DEBIT, mint))?;
    reject(&mut dao, "08-unauthorized", Denial::Authorization, |d| d.apply(mint, ARTIFACT, &forbidden));
    reject(&mut dao, "10-indeterminate", Denial::Indeterminate, |_| gated("Good", "absent"));
    reject(&mut dao, "11-process", Denial::Process, |_| {
        adapter.after_check(|| check(dir, "/nonexistent-core01b-verifier", "Good", "expected")).map(drop)
    });
    reject(&mut dao, "12-operation", Denial::Operation, |d| d.apply("treasury:debit:8", ARTIFACT, &receipt));
    reject(&mut dao, "13-mismatch", Denial::Mismatch, |_| gated("Mismatch", "expected"));
    reject(&mut dao, "14-ambiguous", Denial::Descriptor, |_| adapter.issue(&format!("{pin}request=duplicate\n")).map(drop));
    let artifact = dir.join(ARTIFACT);
    let original = fs::read(&artifact)?;
    reject(&mut dao, "15-staged-substitution", Denial::Artifact, |_| {
        fs::write(&artifact, b"substituted")?;
        let result = adapter.issue(&pin).map(drop);
        fs::write(&artifact, &original)?;
        result
    });
    dao.apply(DEBIT, ARTIFACT, &receipt)?;
    assert_eq!(dao.state, State { balance: 93, consumed: true, replay_count: 1, audit_log: vec![DEBIT] });
    println!("PASS 01-valid");
    reject(&mut dao, "09-replay", Denial::Replay, |d| d.apply(DEBIT, ARTIFACT, &receipt));
    Ok(())
}

fn main() {
    let arg = env::args_os().nth(1).expect("runtime directory");
    let dir = Path::new(&arg).canonicalize().expect("runtime directory");
    let executable = env::current_exe().expect("adapter executable");
    assert_eq!(executable.parent(), Some(dir.as_path()));
    assert!(dir.file_name().unwrap().to_string_lossy().starts_with("runtime-"));
    if let Err(error) = run(&dir) {
        eprintln!("BLOCKED {error:?}");
        std::process::exit(1);
    }
}
