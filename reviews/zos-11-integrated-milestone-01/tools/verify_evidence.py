#!/usr/bin/env python3

"""Verify package integrity and selected evidence consistency.

This utility does not reproduce the original experiments,
execute WebAssembly, authenticate callers, or grant authority.
"""

import base64
import hashlib
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[1]

def require(condition, label):
    if not condition:
        raise SystemExit("FAIL: " + label)

def load(relative):
    return json.loads((ROOT / relative).read_text())

def sha(data):
    return hashlib.sha256(data).hexdigest()

manifest = ROOT / "SHA256SUMS"

require(
    manifest.is_file() and not manifest.is_symlink(),
    "manifest"
)

pins = {}

for line in manifest.read_text().splitlines():

    match = re.fullmatch(
        r"([0-9a-f]{64}) [ *](.+)",
        line
    )

    require(match is not None, "manifest syntax")

    digest, name = match.groups()
    path = pathlib.PurePosixPath(name)

    require(
        not path.is_absolute()
        and ".." not in path.parts
        and "\\" not in name,
        "safe manifest path"
    )

    name = path.as_posix()

    require(
        name != "SHA256SUMS"
        and name not in pins,
        "unique manifest entry"
    )

    pins[name] = digest

actual = set()

for path in ROOT.rglob("*"):

    require(
        not path.is_symlink(),
        "no symbolic links"
    )

    if path.is_file():

        relative = path.relative_to(ROOT).as_posix()

        if relative != "SHA256SUMS":
            actual.add(relative)

    else:
        require(
            path.is_dir(),
            "regular payload entries only"
        )

require(
    actual == set(pins),
    "complete manifest coverage"
)

for name, digest in pins.items():

    require(
        sha((ROOT / name).read_bytes()) == digest,
        "payload identity: " + name
    )

print(f"MANIFEST={len(pins)}/{len(pins)}_PASS")

fixture = (
    ROOT / "evidence/fixture.wasm"
).read_bytes()

descriptor = load(
    "evidence/FIXTURE_DESCRIPTOR.json"
)

digest = hashlib.sha256(fixture).digest()

require(
    len(fixture) == 36 == descriptor["size"],
    "fixture size"
)

require(
    digest.hex() == descriptor["sha256"],
    "fixture SHA-256"
)

require(
    fixture[:8] == b"\x00asm\x01\x00\x00\x00",
    "WASM magic and version"
)

cid = "b" + base64.b32encode(
    bytes([1, 0x55, 0x12, 0x20]) + digest
).decode("ascii").lower().rstrip("=")

require(cid == descriptor["cid"], "raw CIDv1")

print("FIXTURE_SIZE_SHA256_CID=PASS")

runtime = load(
    "evidence/WASMI_REGRESSIONS.json"
)

require(
    runtime["expected"] == runtime["passed"] == 58,
    "runtime counts"
)

require(
    len(runtime["cases"]) == 58
    and all(
        x == "PASS"
        for x in runtime["cases"].values()
    ),
    "runtime evidence consistency"
)

print("WASMI_EVIDENCE_CONSISTENCY=PASS")

replay = load(
    "evidence/REPLAY_MODEL_RESULTS.json"
)

require(
    replay["executed"] == replay["passed"] == 17
    and replay["model_only"] is True
    and replay["execution_authorized"] is False,
    "replay evidence scope"
)

require(
    len(replay["cases"]) == 17
    and len({
        x["id"] for x in replay["cases"]
    }) == 17
    and all(
        x["status"] == "PASS"
        for x in replay["cases"]
    ),
    "replay case consistency"
)

print("REPLAY_EVIDENCE_CONSISTENCY=PASS")

provider = load(
    "evidence/KUBO_PROVIDER_RESULTS.json"
)

require(
    provider["checks_passed"] == 9
    and len(provider["checks"]) == 9
    and all(
        x is True
        for x in provider["checks"].values()
    ),
    "Kubo provider consistency"
)

require(
    provider["operational_execution"] is False,
    "provider safety"
)

rust = load(
    "evidence/KUBO_RUST_RESULTS.json"
)

require(
    rust["rust_cases_passed"] == 6
    and len(rust["cases"]) == 6
    and all(
        x["passed"] is True
        for x in rust["cases"]
    ),
    "Rust evidence consistency"
)

require(
    rust["second_kubo_retrieval"] is False
    and rust["operational_execution"] is False,
    "Rust safety"
)

print("KUBO_RUST_EVIDENCE_CONSISTENCY=PASS")

v2 = load("evidence/V2_MODEL_SUMMARY.json")

require(
    v2["archive_manifest_verified_in_ubuntu"] == 587
    and v2["model_checks_reported_passed"] == 37
    and v2["real_signature_verification"]
        == "NOT_PERFORMED"
    and v2["execution_authorized"] is False,
    "V2 evidence scope"
)

print("V2_MODEL_EVIDENCE_CONSISTENCY=PASS")

matrix = load("TEST_MATRIX.json")

require(
    len(matrix["suites"]) == 12
    and all(
        row["passed"] == row["expected"]
        for row in matrix["suites"]
    ),
    "test matrix consistency"
)

require(
    matrix["operational_authorization"] is False
    and matrix["production_acceptance"] == "BLOCKED",
    "matrix safety"
)

milestone = load("MILESTONE.json")

require(
    milestone["real_action_authorization"]
        == "DISABLED"
    and milestone["dao_credits_authorized"] == "NO"
    and milestone["production_acceptance"]
        == "BLOCKED",
    "final safety status"
)

print("PUBLIC_EVIDENCE_VERIFICATION=PASS")
print("ORIGINAL_EXPERIMENTS_REEXECUTED=NO")
print("FULL_RUNTIME_REBUILD=NO")
print("PRODUCTION_ACCEPTANCE=BLOCKED")
