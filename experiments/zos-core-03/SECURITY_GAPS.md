# Security gaps

- The portable policy recognizes one canonical synthetic receipt. Wider schemas, principal authentication, key rotation, revocation, rollback protection across restored snapshots, and real ledger integration would require separate design and evidence.
- The host and SQLite adapter share the operating-system authority of the lab process. Isolation measurements cover separate SQLite files and CORE-02's fixture rebuild containment. Host compromise, hostile plug-ins and arbitrary user-controlled database paths fall outside the tested contract.
- Strict Ed25519 verification is intentionally conservative. The tests establish native/WASM equivalence for this fixture contract and agreement with the existing OpenSSL adapter for the accepted fixture. They do not establish agreement across all encodings and public keys.
- Input size, guest memory and host verifier elapsed time are bounded. Sustained-load behavior, engine side channels, runtime hardening and hostile multi-tenant deployment were outside this experiment.
- The CORE-02 durability evidence covers process termination and SQLite transaction behavior. Physical power-loss or storage fault recovery remains unverified.
- Production acceptance remains blocked.
