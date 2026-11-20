# Reproduction

Use a fresh extraction inside an isolated lab on Linux x86-64, with Landlock ABI 5 or later, Python 3, the installed Lean 4.35.0 and Rust 1.97.1 executables matching the CORE-01 pins, a system linker, SQLite 3.46.1 with development linker support, OpenSSL Ed25519 support and GNU coreutils. See [the observed dependency identities](evidence/dependencies.log). The harness needs exclusive write access to its working subdirectory.

```sh
sha256sum -c MANIFEST.sha256
(cd core01 && sha256sum -c PUBLIC_MANIFEST.sha256)
(cd core01/rebuild && sha256sum -c PUBLIC_INPUTS.sha256)
export CORE_LEAN=/path/to/installed/lean/bin/lean
export CORE_RUSTC=/path/to/installed/rust/bin/rustc
/usr/bin/python3 -B test.py
```

The test creates a fresh subdirectory for the issuer, compiler outputs and SQLite databases. It regenerates the signed receipt with a fresh synthetic key, verifies the public manifest and original artifact digests, then independently compiles the consumer with the isolated issuer public key. The test runs the same script against normal and crash-instrumented consumers. Its normal exit removes the run directory. Failures can leave a local run directory for diagnosis. Package only the listed manifest files.

For the normal CLI build use `CORE02_TRUSTED_KEY` pointing to the operator-pinned public PEM with `rustc --edition=2021 src/main.rs -o adapter`. Run `adapter init DB` once in the lab, then `adapter consume DB MESSAGE SIG GOOD_OLEAN treasury treasury:debit:7`. Supply the signed message, detached signature and compiled Lean artifact from the independently trusted issuer.
