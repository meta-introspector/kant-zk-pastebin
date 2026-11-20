# Security limitations

This experimental review covers a single synthetic receipt format and debit. The WASM guest has zero imports, and its result only gates a second, trusted verification and a host-owned SQLite transaction. The included verification keys, signature and compiled Lean proof are synthetic fixture data. The deterministic test signer is publicly reproducible and has no operational authority.

The test scope includes malformed inputs, replay, host policy and denial without mutation. It leaves physical power loss, long-running load, key lifecycle, host compromise and production deployment outside the verified scope. The build expects a pinned offline dependency cache and the documented local tools. See [security gaps](SECURITY_GAPS.md) and [trust boundaries](TRUST_BOUNDARIES.md).

Production acceptance remains blocked.
