# PRODUCT-01S6B — Experimental Rust Authority

**Security acceptance: BLOCKED**

**Production status: NO_GO**

This directory is a review-only experimental snapshot.
It is not wired into the runtime, relay, worker, build system,
or deployment configuration.

## Purpose

Review an experimental Rust authority implementation
covering mandatory SQLite reservation, atomic COMMIT,
HMAC receipts, replay handling, and FFI resource cleanup.

The reference Python implementation and selected audit
scripts are included for independent inspection.

## Observed evidence

- Rust/Python protocol comparison: 17/17 matched traces
- Native Rust FFI error-cleanup tests: 14/14 passed
- Rust/Python HMAC and SQLite checks: 33/33 passed
- Experimental crash recovery passed at tested boundaries
- SQLite statement-failure rollback passed

These results apply only to their recorded experimental
scope. They are not formal proofs of production security.

## Blocking findings

### TRUST-ROLLBACK

Restoring a pre-COMMIT SQLite snapshot permits another
COMMITTED response for the same operation.

No duplicate external worker or IPFS side effect was tested.

### TRUST-SAME-UID

An actor with SQLite write access and the HMAC key can
construct a valid-looking COMMITTED record, subsequently
accepted as REPLAY.

HMAC cannot establish an independent trust boundary
against an actor controlling its signing key.

## Additional limitations

- No separately privileged authority service
- No independently trusted anti-rollback witness
- No authenticated Unix socket integration
- No production Rust/WASM relay integration
- No full power-loss or filesystem-fault testing
- No formal FFI memory-safety proof

## Review scope

The files here are reference artifacts, not an installation
or deployment patch.

Do not merge or deploy as a security remediation without
separate design review, integration tests, and approval.

## Evidence archive

Original consolidated evidence bundle:

PRODUCT01S6B02P11L_REVIEW.tar.gz

SHA-256:

823ec3320675ce85c6dd4ab6c7118451f1948025e9a83c9430fa10574999cd91

The archive is retained separately and is not included
in this proposed Git change.
