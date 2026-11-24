# ZOS-INTEGRATION-11 — Kant → CERT03 → SQLite → Lean DENY

**Verdict:** ACCEPT FOR EXPERIMENTAL REVIEW — **NOT PRODUCTION-READY**

**IPFS summary-only review bundle (user-supplied CID):** `bafybeidg6zln4cp57juy3dym7j6hwedwxgylbvgizv7hgkrum2kj6ubsmm`

**Local sealed review archive SHA-256 (reported by ZOS-INTEGRATION-11):**
`4c074328ac2a9c2230662c3e8a9abe5dd08bf98cdce21c3e48d0fcac376b89a6`

## Experimental findings

- Kant `ServiceSpec.Spec` metadata projection retains `name`, `description`, and `kind`, excluding 16 operational fields: **18/18 checks PASS**.
- Synthetic signed nonce-binding experiment: nonce, issuer, audience, and observation included in Ed25519 claims; concurrent SQLite test: **1 recorded, 7 replay-denied**.
- Original CERT03 `issue()` and `PublicVerifier.verify()` successfully reused from pinned source in an isolated lab.
- Valid experimental credential verdict: `CREDENTIAL_ACCEPTED_TEST_ONLY`; replay: `DENY_REPLAY`; modified request not accepted.
- Isolated SQLite database integrity: **PASS**.
- Pinned Lean policy executed after credential verification and returned `DENY:UNTRUSTED_OBSERVATION`.
- Final handoff verified **five sealed experimental evidence sets**. Public archive contains only `README.md`, `SUMMARY.json`, and `SHA256SUMS.txt`.

## Precise scope and limitations

The demonstrated pipeline is **sequential experimental composition**, not end-to-end formally verified authorization. Lean receives only a service name and **does not verify the full signed claim**. The native Rust authority is **not integrated**. Issuer and audience are hardcoded experimental values, credentials use synthetic keys, and no production issuer registry, live service discovery, or complete runtime attestation is established.

The IPFS CID above was supplied by the contributor; this PR **does not claim independent retrieval or matching of the remote IPFS bytes against the local archive SHA-256**.

This repository change is summary-only. The IPFS archive is not a standalone reproducible source build and contains no original runtime code or SQLite data. Do not infer approval or production readiness from passing laboratory checks.

**POSITIVE_EXECUTION=DISABLED**  
**PRODUCTION_ACCEPTANCE=BLOCKED**

**No merge, protected-branch change, production action, wallet/DAO transaction, or execution authorization is requested.**
