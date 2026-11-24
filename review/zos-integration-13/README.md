# ZOS-INTEGRATION-13C — Experimental Rust-to-Lean Digest Binding Review

**Review verdict:** ACCEPT FOR EXPERIMENTAL REVIEW — **NOT PRODUCTION-READY**

This is a documentation-only handoff for a laboratory Lean digest-gate contract and a local Rust-to-Lean fail-closed orchestrator. It does not establish an authenticated IPC protocol or production authorization.

## Public IPFS bundle

- CID, reported by publisher (remote bytes not independently verified here): `bafybeih6faviqanj3vpd2mxo3gg57aubaoom2qx64uq2qg27tz3a5kkr4q`
- Local archive `ZOS-INTEGRATION-13C-public-review.tar.gz` SHA-256: `578be63a02d2297ca74987dbc6c29bed96c262549c3dc38d553a591dbb872110`
- Public archive allowlist: `README.md`, `SUMMARY.json`, `SHA256SUMS.txt`
- Sealed evidence verified locally: 2 experimental sets, 11 files.

## Experimental findings

- A Lean 4.33.0 laboratory contract compared a pinned request digest, service name, and trust status; a theorem for the pinned UNTRUSTED observation compiled with Lean.
- Lean tests: **6/6 PASS**, including modified digest, modified service, forged trust, and missing arguments.
- Local orchestrator verified the Rust binary and Lean source snapshot hashes and invoked the actual Rust verifier before invoking Lean.
- Local Rust→Lean test cases: **9/9 PASS**, comprising one baseline and eight adversarial checks.
- Baseline Rust result: `DENY_POLICY`.
- Baseline Lean result: `DENY_UNTRUSTED_OBSERVATION`.
- Kant request digest: `8a0ff7d4965ec7a5a972ba5408faa9ccd7056cab10d45e6117395def191b2f10`.
- Client-provided claims of successful verification were not used as authority in the tested local orchestration.

## Explicit security boundaries

- Lean **does not independently authenticate Ed25519** or verify the original signed claim.
- The Python orchestrator remains inside the trusted computing base.
- No cryptographically authenticated Rust→Lean IPC or hostile-client isolation has been established.
- Pre-execution snapshot checks **do not eliminate TOCTOU** and no runtime executable dependency closure has been attested.
- A `DENY_POLICY` result is a **denial**, never authorization.
- No sources in the original project were modified; no DAO/wallet transactions or production changes.

`POSITIVE_EXECUTION=DISABLED`

`PRODUCTION_ACCEPTANCE=BLOCKED`

Publication is for experimental review only; it is **not** merge or production approval.
