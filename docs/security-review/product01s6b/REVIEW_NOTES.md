# ZOS PRODUCT-01S6B-02P — Experimental Rust Authority Review

Status: SECURITY_ACCEPTANCE=BLOCKED
Production: NO_GO

## Scope

This package contains selected source snapshots, test scripts,
and integrity-verified experimental reports P08–P11K.

It is not a deployable release and does not demonstrate full
production or worker-level exactly-once execution.

## Confirmed experimental properties

- Mandatory SQLite reservation before COMMIT
- Atomic claims/commits in one SQLite transaction
- Native Rust SQLite FFI with parameter binding
- HMAC-SHA256 receipt calculation consistent with Python
- Crash recovery at explicitly instrumented SIGKILL points
- Rollback after injected SQLite statement errors
- SQL trailing-statement rejection
- SQLITE_TRANSIENT binding and checked finalization
- SQLite close error handling on tested paths
- P11I: 14 native tests and 33 differential checks passed
- P11J: 17/17 protocol response and state comparisons matched

## Reproduced blocking trust gaps (P11K)

1. TRUST-ROLLBACK — HIGH
   Restoring a pre-COMMIT SQLite image permits another
   COMMITTED response for an already previously committed
   request. No external effect duplication was tested.

2. TRUST-SAME-UID — HIGH
   A process with database write access and the HMAC key can
   forge well-formed committed state, accepted as REPLAY.
   The key cannot authenticate against its own holder.

## Further limitations

- No separately privileged authority service demonstrated
- No trusted independent anti-rollback witness
- No authenticated Unix socket protocol in this candidate
- No Rust/WASM integration with the actual relay
- No Lean worker or IPFS side effects executed
- No power-loss proof, sanitizer or formal FFI memory proof
- Fixed protocol traces are not a formal equivalence proof
- Experimental dynamic SQLite/OpenSSL linking on WSL2

## Reviewer priorities

1. Define the authority process and operating-system trust boundary.
2. Determine the anti-rollback threat model and independent witness.
3. Review fail-closed reconciliation after ambiguous COMMIT outcomes.
4. Review native FFI ownership, error paths and HMAC key management.
5. Decide the scope of Rust/WASM integration separately.

## Contents

- sources/: Python reference and hardening-stage Rust source
- tests/: selected validation and adversarial test scripts
- reports/: verified experimental reports P08–P11K
- SHA256SUMS: checksums for package contents

Source files are snapshots, not a reproducible full build system.
No runtime keys, SQLite data files or executable binaries are included.

No security acceptance or permission to merge is implied.
