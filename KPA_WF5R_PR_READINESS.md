# KPA-WF5R — Experimental Envelope Integrity Integration

## Scope
Additive Linux-only GET /integrity/{id} endpoint for
meta-introspector/kant-zk-pastebin.

## Implemented
- SHA-256 of the complete stored paste envelope
- Optional PasteIndex.envelope_witness
- Local MATCH / MISMATCH / UNVERIFIABLE / ERROR statuses
- Bounded file and index reads
- O_NOFOLLOW descriptor-based access
- Metadata and byte-count consistency checks
- Send-compatible Actix blocking response handling
- Rename invalidation of stale envelope witnesses
- Direct libc dependency and lockfile update

## Verification
- Rust syntax parsing: PASS
- Git whitespace validation: PASS
- Selected standalone tests: PASS
- Seven permanent Rust regression tests: NOT RUN
- Full application build: BLOCKED (private NORA dependencies)
- HTTP integration tests: NOT RUN
- Production deployment: NOT RUN

## Limitations
- MATCH proves local byte/hash agreement only.
- No independent authenticity or Lean-kernel attestation.
- File reads are not atomic snapshots.
- Historical and reindexed entries may lack envelope_witness.
- Index writes and rename operations are not transactional.
- The 64 MiB index and 512 MiB envelope limits need review.
- No production-readiness claim.

## Verdict
EXPERIMENTAL — OPEN — NOT PRODUCTION-READY.
Do not merge as a validated security fix without authentic
build and integration-test evidence.
