# Historical CORE-03 independent audit

The implementation was copied through a source tar into a fresh extraction. The second build used an empty Cargo target directory and the existing offline crate cache. Both builds checked the locked package archives and the unpacked source bytes. The audit compared the native executable and WASM module byte for byte, and diffed the case results and all SHA-256 vector digests.

The CORE-02 archive bundled in the original handoff matches the original Git subtree across all 61 files. The audit recomputed the tree and five fixture blob IDs from extracted bytes. The original JobVerifier commit was also checked in its local repository. See [source identities](evidence/source-identities.log).

The independent run instantiated an import-free WASM module, checked the memory cap and verified the full shared matrix. The authority harness sent the historical Lean issuer's authenticated receipt through WASM to the pinned CORE-02 adapter, verified the full resulting audit record, and verified replay through both runtimes. Negative host cases included an unauthorized principal, invalid bytes accepted by a simulated guest, indeterminate output from a broken module and a verifier timeout. Each left the synthetic database at its initial logical state. The control database hash stayed constant.

CORE-02 was independently extracted and rebuilt with its original pinned Lean and Rust versions. Its regression rebuilt the Lean issuer and verified the artifact, descriptor and message against archived digests. The SQLite regression exercised contention, rollback, concurrent exactly-once processing, actual before- and after-commit SIGKILL, and schema and integrity rejection.

## PUB01 reproduction

Use the installed Linux x86_64 toolchains and cached Cargo packages. Keep output paths inside a fresh isolated lab. Set absolute paths for the CORE-02 tools to the installed Lean 4.35.0 and Rust 1.97.1 used in the regression log.

```sh
sha256sum -c MANIFEST.sha256
bash build.sh /absolute/lab/build
CORE_LEAN=/absolute/path/to/lean CORE_RUSTC=/absolute/path/to/rustc \
  bash regress.sh /absolute/lab/core02-regression /absolute/repository-with-pr39
bash package.sh /absolute/lab/repacked.tar.gz
```

Build and test logs are included under `evidence/`. `package.sh` normalizes archive ordering, metadata and gzip time. The archive checksum travels in a sidecar outside the archive. The audit is a clean-room rebuild of the supplied sources on the same installed toolchains and cache. This experiment has one synthetic receipt format and no production acceptance.

PUB01 repeats the differential and host tests from its sanitized archive. See [PUB01 reproduction](REPRODUCTION.md), [publication rebuild](PUBLICATION_REBUILD.md) and the [sanitization map](SANITIZATION_MAP.md).
