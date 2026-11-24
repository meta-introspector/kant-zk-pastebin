# ZOS-SDISC-02F-07 — Service Discovery experimental review

**Status:** ACCEPT FOR EXPERIMENTAL REVIEW — **NOT PRODUCTION-READY**

**IPFS sanitized summary bundle:** `bafybeie2xpz2bb7rwawmb5ilscgxotfak3pvhmfbpnkr2h2vn35qptco44`

**Local review archive SHA-256 (reported by the sealed handoff audit):**
`a15b7196da779008b618b1172bbab374bfed0ba99efb79075e11d5674d1d0b81`

## Experimental results

- Ed25519 credential binding and durable SQLite replay rejection (synthetic keys; no production identity).
- Atomic nonce + untrusted observation recording: **30/30** checks in the isolated SQLite model.
- Signed Ed25519 + atomic observation adaptor: **25/25** checks.
- Controlled SIGKILL recovery of the integrated adaptor: **6/6** scenarios.
- Rust normalizer + Ed25519 + SQLite + deny-only Lean policy integration: **21/21** checks.
- Adversarial Lean policy boundary: **26/26** checks.
- SHA-256 inventory of **5,022** files observed/inventoried across the Lean runtime research; **not a complete attestation**.
- Verified source snapshot: **3/3** scenarios.
- Controlled TOCTOU experiments: **4/4** scenarios; protection remains **partial**.
- Final audit: **10 evidence sets** verified and summary-only public archive safety check passed.

## Security interpretation

A signed, replay-protected service observation is still **untrusted** and **does not grant execution authority**. Policy checks remain deny-only. `OBSERVATION_RECORDED_NO_AUTHORITY` confirms storage, not authorization.

**Not proven:** complete runtime closure/attestation, resistance to concurrent same-user snapshot tampering or dynamic-library replacement at point of use, authenticated live network transport, production trust registry transitions, physical power-loss durability, or formal correctness of the entire multi-process composition.

## Publication scope and limitations

The linked IPFS bundle is a **sanitized summary** with evidence hashes; it does **not** contain the original source, reproducible build closure, SQLite databases, private keys, or the Lean toolchain. The CID is supplied for review; no claim is made here that the remote IPFS payload was independently fetched and checked against the archive SHA-256.

This GitHub change records a summary and pointers only. It does not merge code, enable new services, authorize DAO actions, or change production configuration.

**POSITIVE_EXECUTION=DISABLED**

**PRODUCTION_ACCEPTANCE=BLOCKED**
