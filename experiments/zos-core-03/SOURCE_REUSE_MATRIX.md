# Source reuse matrix

| Component | Verified identity | CORE-03 use |
|---|---|---|
| CORE-01 | `0f0726575b5b608a8da8572dd93cac24b9187aec` | Confirmed local commit and draft PR head. Reused the fixture format and archived issuer evidence carried by CORE-02, plus the pinned Lean issuer via its regression harness. |
| CORE-02 | `502827ec3db0186b681008f419a7942fd524dce8`, experiment subtree `37d71100d020f13415dd1c42fd09054d14d1b4fa` | The original handoff pinned the complete 61-file public archive. PUB01 includes only the three adapter source files and nine receipt and fixture files. Their bytes match the public Git blobs recorded in the evidence. The full unmodified regression runs from the exact PR #39 Git subtree. |
| JobVerifier | `221cf074aaa3146f41863532a4fd9478dcba044f` | Compared Check, Good, Ref, SorryCase and Mismatch fixture bytes directly with the original commit objects. The rebuild rehashes the five packaged Git blobs. |
| Compiled Lean fixture | `56a7ed934806d8f6e33bd3d938a325761e741dbe534f6e295dc9901d8296a52b` | Reused the installed CORE-02 baseline's Good.olean. Both verifier targets validate its bytes against the signed descriptor. The original regression independently compiles and verifies the same digest. |
| Upstream pastebin-wasm | Inspected at CORE-02 commit | Its pure-Rust SHA-256 and cdylib approach applies here. Its wasm-bindgen surface, CID codec and encryption serve a different contract. CORE-03 uses an import-free byte ABI and directly uses the same sha2 0.10 series. |
| Installed cryptography | ed25519-dalek 2.2.0, curve25519-dalek 4.1.3, sha2 0.10.9 | Existing Rust implementations with default features disabled. Cargo.lock pins the complete dependency graph and depcheck.py checks cached contents. |

CORE-02's exact receipt comparison, operation comparison and digest extraction are standalone logic. The native file reader, OpenSSL scratch and subprocess handling, and SHA-256 subprocess require trusted host capabilities. The portable core preserves the checks and replaces host crypto calls with pure Rust. The authority, schema checks, replay lookup, available-balance check, receipt/effect writes, and commit remain with the host.

Both referenced upstream PRs were observed as open drafts with the specified head commits. See [CORE-01 PR #38](https://github.com/meta-introspector/kant-zk-pastebin/pull/38) and [CORE-02 PR #39](https://github.com/meta-introspector/kant-zk-pastebin/pull/39).
