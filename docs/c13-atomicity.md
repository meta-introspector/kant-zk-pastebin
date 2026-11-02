# C13-2 Atomic Upload Flow & Security Guarantees

This document describes the C13-2 protocol, implemented to secure the upload path against TOCTOU (Time-of-Check to Time-of-Use) attacks, orphaned data, and content substitution.

## The C13-2 State Machine

Every upload transitions through a strict state machine in SQLite (`c13_transactions` table):

1. **PREPARED**: A transaction is created with the expected `witness` (SHA-256 of the upload) and `local_cid`. At this stage, the upload is **not** HTTP accessible.
2. **Content Bind & Verify**: The file is written to the spool and added to IPFS. The resulting root CID is validated:
   - It must be canonical (SHA2-256, 32 bytes).
   - Codec must be raw (`0x55`) or DAG-PB (`0x70`).
   - The UnixFS DAG is traversed, and the resulting bytes are hashed. The SHA-256 must exactly match the `witness`.
3. **COMMITTED**: If and only if the content binding succeeds, the spool index is updated, the CID alias is published, and the SQLite transaction is marked `COMMITTED` with the `ipfs_root_cid`.
4. **UNCERTAIN**: If a crash occurs after the IPFS marker but before SQLite commit, the state is reconciled. If SQLite cannot confirm the commit, the state remains `PREPARED`/`UNCERTAIN` and the content is never exposed over HTTP.

## Addressing Open Risks (Mike's Audit)

- **Index locking does not make TXT, CID and index atomic together**: The C13-2 flow forces the SQLite state machine to be the single source of truth. The index and alias are only written *after* the root CID is bound and verified.
- **Path/source authenticity**: We enforce cryptographic authenticity. The `ipfs_root_cid` is mathematically bound to the uploaded content via the SHA-256 witness.
- **Crash recovery**: We added distinct pre-commit and post-commit fault probes (`c13_sqlite_precommit_fault_probe`, `c13_sqlite_commit_fault_probe`) to validate recovery paths without exposing partial data.
- **DAG-PB Read Path**: Previously, `/ipfs/{cid}` served the raw protobuf block for files >256KB. It now reconstructs the entire UnixFS DAG back into the original file bytes.
