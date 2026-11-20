# Crash recovery

Two independent runs each exercised two precommit and two postcommit SIGKILL cases across fresh databases. Each worker notified the harness through stdout after either both INSERTs returned or COMMIT returned. The worker parked before its final acknowledgment. The parent sent SIGKILL and verified exit status `-9`. The checkpoint controls ordering and the OS signal performs the crash.

| Cut point | Complete state on fresh connection | Retry and replay |
|---|---|---|
| Before commit, after both writes | Zero receipts, zero effects, 100 units. Integrity and FK checks passed. | New process applied once, second process returned REPLAY, verified one receipt and effect with 93 units. |
| After commit, before acknowledgment | One matching receipt and effect, 93 units. Integrity and FK checks passed. | Both new processes returned REPLAY and left the state unchanged. |

The case separates observed process-crash durability from behavior under device-level power interruption. An independent historical INT05 worker run also passed six actual SIGKILL cases, including one cut before its second write. CORE-02's proof of rollback after only the first write comes from the executable write-failure and explicit-abort tests.
