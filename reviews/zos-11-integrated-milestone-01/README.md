# ZOS-11 — Integrated Experimental Milestone 01

Date: 2026-11-26

## Verdict

EXPERIMENTAL REVIEW CANDIDATE — NOT PRODUCTION-READY.

## Architecture

Offline Kubo/IPFS retrieval
-> sealed Rust integrity gate
-> bounded consumer
-> verified immutable Rust artifact
-> unified authority boundary
-> operational DENY.

## Experimental results

- Wasmi runtime: 58/58 historical regressions.
- Rust-Lean-WASM denial composition: 8/8.
- Private execution boundary: 8/8.
- External API visibility: 9/9.
- Non-test external consumer: 9/9.
- Canonical encoding: 7/7 vectors.
- Independent replay model reproduction: 17/17.
- Sealed Kubo runtime identities: 13/13.
- Kubo provider integration: 9/9.
- Kubo-to-Rust integration: 6/6.
- Latest integration manifest: 509/509.

These are separate experimental suites, not a single
end-to-end security proof.

## Latest integration

A synthetic 36-byte WASM fixture was added to a fresh,
offline Kubo repository, retrieved through the qualified
integrity gate, independently checked, and passed to
the Rust execution boundary.

The artifact was denied because it did not match the
historical authority fixture. No Lean subprocess was
observed for this particular artifact.

No operational WASM execution occurred.

## Limitations

- General proof-to-artifact applicability is unresolved.
- Cryptographic caller authentication is not qualified.
- Authenticated conflicting requests are not qualified.
- Policy identity binding is still under development.
- Full runtime closure is not established.
- Strict end-to-end deadline is not established.
- The cross-process handoff uses a reverified file.
- This package contains selected evidence summaries,
  not the complete sources or independently rebuildable
  laboratory.
- Historical evidence is retained in private laboratories.

## Safety

REAL_ACTION_AUTHORIZATION=DISABLED
DAO_CREDITS_AUTHORIZED=NO
PRODUCTION_ACCEPTANCE=BLOCKED

## Verify package integrity

Run from the extracted package directory:

    sha256sum --strict -c SHA256SUMS

Integrity verification does not establish the truth
of experimental claims or production readiness.

## Additional review material

- TECHNICAL_REPORT.md
- ARCHITECTURE.md
- SECURITY_BOUNDARIES.md
- ROADMAP.md
- PROVENANCE.md
- TEST_MATRIX.json
- contracts/INTEGRATION_REVIEW.md
- provenance/
- evidence/
- tools/verify_evidence.py

Run the standalone evidence verifier:

    python3 -I -B tools/verify_evidence.py

This package includes an evidence verification utility,
not the recovered ZOS runtime implementation.
