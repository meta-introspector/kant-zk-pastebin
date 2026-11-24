# ZOS-INTEGRATION-12F — Experimental interoperability review

**Status:** ACCEPT FOR EXPERIMENTAL REVIEW — NOT PRODUCTION-READY.

This is a **summary-only** handoff for the Kant Lean Worker → CERT03 Ed25519 → Rust semantic verifier → Lean policy laboratory integration. It is not a production security attestation or authorization.

## IPFS review bundle

- **CID (reported by the publisher; not independently fetched or verified here):** `bafybeibdhqxcckv5w5fqsi225zjlbqldodajlgyknn3tco7dtdorrheudq`
- **Locally verified SHA-256 of `ZOS-INTEGRATION-12F-public-review.tar.gz`:** `72f37a0c33816910baa6d8a824840526cf51b7532af064e8ca02b51f01ef8bd5`
- Public bundle allowlist: `README.md`, `SUMMARY.json`, `SHA256SUMS.txt`; no raw logs, source tree, binary, database, or key material.
- Local handoff report verified **4 sealed evidence sets / 30 files**.

## Experimental observations

1. CERT03 and Rust `Claims` schemas have nine corresponding fields.
2. The original Rust trust configuration rejected a separate CERT03 synthetic credential: `DENY_SIGNATURE`.
3. A separate **synthetic laboratory** Rust build using the same public key, domain, and request digest as CERT03 verified the unchanged signed message and returned `DENY_POLICY`.
4. Original CERT03 verifier accepted its test credential as `CREDENTIAL_ACCEPTED_TEST_ONLY` and rejected replay as `DENY_REPLAY`.
5. The signed claim request digest was matched to the projected Kant observation: `8a0ff7d4965ec7a5a972ba5408faa9ccd7056cab10d45e6117395def191b2f10`.
6. The pinned Lean policy independently returned `DENY:UNTRUSTED_OBSERVATION`.

## Boundaries / gaps

- The successful Rust verification used a synthetic trust profile; the original Rust deployment public key was **not** replaced.
- Lean currently receives **only the service name**; it does **not** verify the signed claim or request digest.
- Native Rust SQLite journal integration is not proven in this sequence.
- Reproducible executable closure and production trust attestation are not established.
- Results show sequential experimental verification, **not** a fully verified end-to-end authorization boundary.
- No DAO/wallet transactions, merges, protected-branch edits, or production changes.

**POSITIVE_EXECUTION=DISABLED**

**PRODUCTION_ACCEPTANCE=BLOCKED**

Publication is for review, not approval.
