# Verification and host interfaces

`verify_frame(&[u8]) -> Outcome` is the Rust entry point. The WASM entry points expose `memory`, `frame_ptr()`, `frame_capacity()`, and `verify(length)`. Write one complete frame to the staging region and call `verify` synchronously. Each field has a four-byte unsigned little-endian length immediately followed by its bytes.

| Field | Maximum bytes | Rules |
|---|---:|---|
| Receipt message | 4096 | Exact CORE-01 prefix and pinned descriptor, including line endings and final newline |
| Detached Ed25519 signature | 64 | Exactly 64 raw bytes |
| Verification key | 32 | Exactly 32 raw public-key bytes from trusted host configuration |
| Artifact | 1048576 | Actual artifact bytes hashed in the core |
| Requested operation | 64 | Exact ASCII `treasury:debit:7` |

Length, order, spelling, whitespace, line endings, digest encoding, and the final newline are part of the contract. The receipt bytes remain identical to CORE-02. Length framing is new and external to the signed message. The parser rejects any trailing data. Signatures cover the canonical message bytes. The signed descriptor fixes the replay domain, request, artifact hash and operation.

| Number | Result |
|---:|---|
| 1 | Authenticated |
| 2 | Malformed framing, key length or signature length |
| 3 | Input length exceeds a bound |
| 4 | Key decoding or strict signature verification failed |
| 5 | Message differs from the canonical receipt |
| 6 | Artifact digest differs from the signed pin |
| 7 | Operation differs from the signed pin |
| 8 | Indeterminate |

The core checks framing and lengths, signature, canonical receipt, operation and artifact in that order. The host API in `host.py` takes a trusted DB location, adapter, verifier command, key and principal plus candidate message, signature, artifact and operation bytes. It requires the configured principal and operation before verification. Only exact status 1 from the configured verifier permits independent native verification and the SQLite transaction. Apply and replay are distinct host outcomes.
