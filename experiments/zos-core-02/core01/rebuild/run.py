"""Public derivative of the CORE-01C runner."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent
FIXTURES = ROOT.parent / "intake" / "fixtures"
COMMIT = "221cf074aaa3146f41863532a4fd9478dcba044f"
LEAN = Path(os.environ["CORE_LEAN"]).resolve(strict=True)
LEAN_COMMIT = "eb6cafb7290e8bd5f2937522d8d804f58f02bafc"
RUST = Path(os.environ["CORE_RUSTC"]).resolve(strict=True)
OPENSSL = "/usr/bin/openssl"
LEAN_SHA256 = "bf8d54e4714cc4b03d3f6bb34c83b7202b87e49c8bfcbff6895c085bb90ceb38"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    os.umask(0o077)
    evidence = Path(tempfile.mkdtemp(prefix="evidence-", dir=ROOT))
    print(evidence.relative_to(ROOT.parent), flush=True)
    commands = evidence / "commands.jsonl"
    phase = "Step 1"
    verdict = "BLOCKED_INTEGRATION"
    failure = None
    passed = []
    source_ids = {}
    inputs_verified = False
    try:
        with commands.open("x") as log:
            if any(ROOT.glob("runtime-*")):
                raise RuntimeError("A previous private runtime directory exists")
            with tempfile.TemporaryDirectory(prefix="runtime-", dir=ROOT) as directory:
                runtime = Path(directory)
                env = {"PATH": f"{LEAN.parent}:/usr/bin:/bin", "LC_ALL": "C", "HOME": directory,
                       "TMPDIR": directory, "LEAN_PATH": directory, "CORE_LEAN": str(LEAN)}
                aliases = {str(evidence): "<evidence>", str(runtime): "<runtime>",
                           str(ROOT): "<rebuild>", str(LEAN): "<CORE_LEAN>",
                           str(RUST): "<CORE_RUSTC>", str(LEAN.parent): "<lean-bin>",
                           str(RUST.parent): "<rust-bin>"}

                def portable(value):
                    for real, label in aliases.items():
                        value = value.replace(real, label)
                    return value

                def run(args, *, cwd=runtime, binary=False, required=True, timeout=60):
                    args = list(map(str, args))
                    out = subprocess.run(args, cwd=cwd, env=env, capture_output=True, timeout=timeout)
                    record = {"argv": list(map(portable, args)), "cwd": portable(str(cwd)),
                              "exit": out.returncode,
                              "stderr": portable(out.stderr.decode(errors="replace"))}
                    if binary:
                        record["stdout_sha256"] = digest(out.stdout)
                    else:
                        record["stdout"] = portable(out.stdout.decode(errors="replace"))
                    log.write(json.dumps(record) + "\n")
                    log.flush()
                    if required and out.returncode:
                        if re.search(rb"permission denied|operation not permitted", out.stderr, re.I):
                            raise PermissionError(f"Access denied running {args}")
                        raise RuntimeError(f"Exit {out.returncode} running {args}")
                    return out

                run(("/usr/bin/sha256sum", "-c", "PUBLIC_INPUTS.sha256"), cwd=ROOT)
                original_manifest = (ROOT / "PUBLIC_INPUTS.sha256").read_bytes()
                rows = re.findall(r"\| (minimal/\S+) \| ([0-9a-f]+) \|",
                                  (ROOT / "SOURCE_IDENTITY.md").read_text())
                if len(rows) != 5:
                    raise RuntimeError("Expected five pinned source paths")
                for path, blob in rows:
                    name = Path(path).name
                    data = (FIXTURES / name).read_bytes()
                    header = f"blob {len(data)}\0".encode()
                    if hashlib.sha1(header + data).hexdigest() != blob:
                        raise RuntimeError(f"Source identity mismatch for {path}")
                    (runtime / name).write_bytes(data)
                    source_ids[path] = {"git_blob": blob, "sha256": digest(data)}

                shutil.copyfile(ROOT / "source/Invalid.lean", runtime / "Invalid.lean")
                inputs_verified = True

                phase = "Step 2"
                shutil.copyfile(ROOT / "source/seam_step2.rs", runtime / "seam.rs")
                lean_version = run((LEAN, "--version")).stdout.decode()
                if f"version 4.35.0," not in lean_version or f"commit {LEAN_COMMIT}," not in lean_version:
                    raise RuntimeError("Lean version mismatch")
                lean_hash = digest(LEAN.read_bytes())
                if lean_hash != LEAN_SHA256:
                    raise RuntimeError("Lean executable digest mismatch")
                rust_version = run((RUST, "--version", "--verbose")).stdout.decode()
                if "commit-hash: 8bab26f4f68e0e26f0bb7960be334d5b520ea452" not in rust_version:
                    raise RuntimeError("Rust compiler version mismatch")
                run((OPENSSL, "version"))
                run((RUST, "--edition=2021", "seam.rs", "-o", "seam"))
                for module in ("Ref", "Good", "SorryCase", "Mismatch"):
                    run((LEAN, "-o", f"{module}.olean", f"{module}.lean"))
                descriptor = (
                    "zos.core01b.descriptor.v1\njob=fixture-true-v1\n"
                    f"commit={COMMIT}\ntoolchain=lean-4.35.0-{LEAN_COMMIT}\n"
                    "module=Good\ntarget=target\nreference=Ref.expected\n"
                    "proposition=True\npolicy=empty-axioms\nreplay-domain=zos.core01b.synthetic.v1\n"
                    "request=fixture-request-0001\noperation=treasury:debit:7\n"
                )
                for field, name in (
                    ("checker", "Check.lean"), ("source", "Good.lean"),
                    ("reference-source", "Ref.lean"), ("artifact", "Good.olean"),
                    ("reference-artifact", "Ref.olean"),
                ):
                    descriptor += f"{field}-sha256={digest((runtime / name).read_bytes())}\n"
                descriptor += f"lean-binary-sha256={lean_hash}\n"
                (runtime / "descriptor.txt").write_text(descriptor, encoding="ascii")
                for name in ("issuer", "other"):
                    run((OPENSSL, "genpkey", "-algorithm", "ED25519", "-out", f"{name}-key.pem"))
                run((OPENSSL, "pkey", "-in", "issuer-key.pem", "-pubout", "-out", "trusted-public.pem"))
                run((OPENSSL, "pkey", "-in", "other-key.pem", "-pubout", "-out", "other-public.pem"))
                test = run((runtime / "seam", runtime), required=False, timeout=240)
                (evidence / "tests.stdout.log").write_bytes(test.stdout)
                (evidence / "tests.stderr.log").write_bytes(test.stderr)
                passed = sorted(map(int, re.findall(rb"^PASS (\d\d)-", test.stdout, re.M)))
                for name in ("Check.lean", "Ref.lean", "Good.lean", "SorryCase.lean", "Mismatch.lean",
                             "Invalid.lean", "descriptor.txt", "trusted-public.pem",
                             "other-public.pem", "Good.olean", "Ref.olean", "SorryCase.olean", "Mismatch.olean"):
                    shutil.copyfile(runtime / name, evidence / name)
                if re.search(rb"permission denied|operation not permitted", test.stdout + test.stderr, re.I):
                    raise PermissionError("Access denied during the executable matrix")
                if test.returncode or passed != list(range(1, 16)):
                    raise RuntimeError(f"Executable matrix incomplete or failed (exit {test.returncode})")
                for name in ("message.bin", "signature.bin"):
                    shutil.copyfile(runtime / name, evidence / name)
                run((OPENSSL, "pkeyutl", "-rawin", "-verify", "-pubin", "-inkey", "trusted-public.pem",
                     "-in", "message.bin", "-sigfile", "signature.bin"), cwd=evidence)
                if digest(LEAN.read_bytes()) != lean_hash:
                    raise RuntimeError("Lean binary changed during execution")
                if (ROOT / "PUBLIC_INPUTS.sha256").read_bytes() != original_manifest:
                    raise RuntimeError("Input manifest changed during execution")
                run(("/usr/bin/sha256sum", "-c", "PUBLIC_INPUTS.sha256"), cwd=ROOT)
            verdict = "ACCEPT_FOR_EXPERIMENTAL_REVIEW"
    except (OSError, subprocess.TimeoutExpired) as error:
        verdict = "BLOCKED_ENVIRONMENT"
        failure = str(error)
    except RuntimeError as error:
        failure = str(error)
    summary = {"verdict": verdict, "production": "BLOCKED", "phase": phase,
               "failure": failure, "passed_cases": passed, "planned_cases": 15,
               "preserved_inputs_verified": inputs_verified, "source_commit": COMMIT,
               "source_identities": source_ids}
    (evidence / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))
    return verdict != "ACCEPT_FOR_EXPERIMENTAL_REVIEW"


if __name__ == "__main__":
    raise SystemExit(main())
