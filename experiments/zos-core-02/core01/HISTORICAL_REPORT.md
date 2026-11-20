# Historical CORE-01C-R1 report — derived public copy

This copy describes the earlier CORE-01C run. Evidence paths refer to the original handoff.

**Verdict: ACCEPT_FOR_EXPERIMENTAL_HANDOFF**

**Production acceptance: BLOCKED**

The independent offline rebuild compiled the Rust adapter with rustc 1.97.1 and built four Lean fixtures with Lean 4.35.0 at commit `eb6cafb7290e8bd5f2937522d8d804f58f02bafc`. The checker executed from Lean source. The invalid-proof fixture failed compilation as expected. The four rebuilt `.olean` files, descriptor and signed message matched CORE-01B byte for byte. The rebuilt adapter includes the documented path guard change.

## Experiment results

15 passed, 0 failed, 0 skipped. The authorized synthetic debit changed balance from 100 to 93 and produced one consumed request, one replay record and one audit entry. Each of the 14 rejection cases checked the expected denial and asserted whole-state equality, covering balance, consumed status, replay count and audit log. The replay snapshot was taken after the successful debit.

| Case | Observed outcome |
|---|---|
| 01 | Authorized debit accepted |
| 02 | Invalid Lean proof rejected by compiler |
| 03 | Proof using `sorry` rejected |
| 04 | Wrong artifact rejected |
| 05 | Descriptor substitution rejected |
| 06 | Tampered receipt rejected |
| 07 | Wrong key rejected |
| 08 | Authentic but unauthorized mint rejected |
| 09 | Replay rejected |
| 10 | Missing expected declaration returned checker error and was rejected |
| 11 | Missing verifier executable exited 127 and was rejected |
| 12 | Genuine receipt substituted into a different allowed operation was rejected |
| 13 | Statement mismatch rejected |
| 14 | Ambiguous descriptor rejected |
| 15 | Staged artifact substitution rejected |

The requested negative-control reruns are cases 04, 05, 08, 09, 12, 14 and 15 in this matrix. An independent OpenSSL invocation accepted the exported Ed25519 receipt with the run's pinned public key and rejected it with the alternate key. The signed payload contained the exact exported descriptor and the verifier recomputed five descriptor digests from source and artifact bytes.

## Provenance and write boundary

CORE-01B manifest SHA-256 was `33172f82f47a3d262b3efdcbe05a3822a5cea5a436d4f739d3a503c63b480de6`. All 58 entries verified before and after the rebuild. Five Lean inputs matched the tracked checkout bytes and immutable blobs of JobVerifier commit `221cf074aaa3146f41863532a4fd9478dcba044f`. Git access used read-only plumbing with optional locks and lazy fetch disabled. The launcher performed the build from the verified staged copies with installed tools.

The laboratory was created under the private CORE-01C workspace. Staging and packaging targeted this directory. The build and matrix inherited a Landlock ABI 7 rule granting filesystem creation, write opens, removal, truncation, and link or rename access only inside the laboratory's `handoff` directory. TCP bind and connect were denied. The preflight confirmed local write/unlink and rejected symlinks or multiply linked regular files in the staging tree. The original sandbox denied ptrace, so containment evidence comes from the enforced Landlock rule and lab-local write probe. The rebuild completed without a write denial. The launcher cleaned up the temporary synthetic private keys.

The Rust patch removes the CORE-01B path from the executed adapter and verifies that the canonical runtime directory contains the adapter executable. The historical Step 1 adapter is preserved for intake verification. The launcher patch switches from repository reads during the rebuild to Git-blob validation of preverified staged fixtures. Both changes are recorded in unified diffs.

The experiment assumes trusted local tools, launcher and Lean sysroot. Concurrent substitution by another same-UID process, independent kernel replay, durable replay protection and production signing authority remain outside the demonstrated guarantees.

## Evidence and reproduction

- Build command transcript, executable, matrix stdout/stderr and receipt exports are in `rebuild/evidence-d30tdiz_/`.
- Independent authentication and state-count verification are in `logs/independent-verification.log`.
- The provenance, CORE-01B integrity, isolation and comparison logs are in `logs/`.
- Exact patches are in `source-path.patch` and `runner.patch`. Inputs are in `intake/`.
- From an extracted handoff, run `sha256sum -c MANIFEST.sha256`. To rebuild, run `/usr/bin/python3 -B rebuild/isolate.py` with the recorded Linux x86-64, Landlock and installed toolchain paths. The runner prints the fresh evidence directory. Verify that export with `/usr/bin/python3 -B rebuild/verify.py <evidence-directory>`.
- The archive is deterministic for this evidence snapshot. New runs create fresh synthetic keys, signatures and runtime directory names.
