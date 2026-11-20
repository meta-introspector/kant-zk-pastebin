# PUB01 independent rebuild

Two separate extracted copies of the sanitized candidate were built with empty target directories. The offline builds verified cached packages against the lockfile. The native executables and real WASM modules matched byte for byte across both runs and matched the original CORE-03 binary hashes. All 24 shared result codes and input hashes matched the original evidence. The module ran in Node.js 22.23.4 and passed the import, memory growth and loader checks.

The host independently verified the archived Lean receipt before committing exactly one synthetic debit and its audit record. The suite exercised eight negative host cases, including a forged guest success, misconfigured or indeterminate verification, and unauthorized operation and principal. The repeated attempts stayed at one debit, and the isolated control database stayed byte-identical.

The full CORE-02 regression passed from the pinned Git subtree of the publicly viewable PR #39. It is a separate replay from the self-contained portable build and host matrix. The two public builds require the specified installed tools and cached locked crates.

The new logs are allowlisted records selected from the actual PUB01 runs. Build transcripts with local paths and process addresses stay in the isolated lab. Historical transcripts with substitutions are separately listed with their original digests.

- [Differential evidence](evidence/pub01-differential.log)
- [Host authorization evidence](evidence/pub01-host-authorization.log)
- [CORE-02 replay evidence](evidence/pub01-core02-regressions.log)
- [Sanitization map](SANITIZATION_MAP.md)
