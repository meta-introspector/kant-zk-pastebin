# Executable test matrix

Both the initial build and the independent build ran the matrix. Each applicable denial compares the complete committed receipt table, effect table and synthetic balance with the pre-request snapshot. The corrupt-file test checks unchanged file bytes and no journal creation.

| Scenario | Boundary and result |
|---|---|
| Valid receipt | Fresh isolated Lean issuance, Ed25519 verification, exact pin, commit and independent SQLite read verifying one receipt and effect and 93 units |
| Same-process replay and restart replay | Stable `REPLAY` with one debit and unchanged rows |
| Multiprocess replay | 12 worker processes with independent SQLite connections, one `APPLIED` and 11 `REPLAY` |
| Invalid signature, wrong key, empty signature | Ed25519 failure, separate build with the wrong embedded public key, and malformed envelope denial |
| Modified artifact digest | Authenticated message and altered compiled artifact bytes reached independent digest comparison |
| Descriptor and operation substitution | Policy denial on supplied operation; Ed25519-valid messages signed with a separate test pin exercised exact-byte rejection for changed proposition and operation fields |
| Unauthorized identity | Valid receipt paired with a foreign DAO policy identity |
| Invalid proof, sorry and indeterminate | Real Lean/compiler diagnostics and issuance denial in unmodified isolated CORE-01 executable. Separate consumer attempts with unsigned claims were denied on the same fresh DB. This is a two-stage check. |
| Forged verifier acceptance | Ed25519-valid test message with altered basis fails exact pin |
| Busy, write failure and partial rollback | Independent SQLite writer lock yielded SQLITE_BUSY. Test hook switched the active connection to query-only after receipt insertion, yielding real SQLITE_READONLY from the second write. Separate injected error forced rollback after insertion. |
| Duplicate request identity | Signed duplicate request field and signed unknown request denied. Independently attempted direct duplicate database insertion; SQLite constraints rejected it. |
| Before and after commit SIGKILL | Two actual signals at each cut point. Reopen inspection, authenticated retry and replay verified for all four. |
| Database corruption and compatibility | Invalid database header, unsupported user version and unexpected trigger denied. Independently checked integrity, enforced deferred links and rejected committing one-sided deletion. |

Raw evidence is in [integration.log](evidence/integration.log) and [independent-rebuild.log](evidence/independent-rebuild.log).
