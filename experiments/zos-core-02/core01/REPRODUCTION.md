# Reproduce the public CORE-01C experiment

This public package is a derivative of the CORE-01C handoff. Use Linux x86-64 with Landlock ABI 5 or later, Python 3, GNU coreutils, a system linker and OpenSSL with Ed25519 support. The recorded run used OpenSSL 3.5.5, Lean 4.35.0, and rustc 1.97.1. The runner checks the Lean version, commit and executable digest and the Rust compiler commit; see the build transcript for exact identities. Use already installed toolchains.

Run from the extracted package root. Set `CORE_LEAN` and `CORE_RUSTC` to paths to the actual installed executables; toolchain manager shims may fail the pinned Lean digest or resolve a different version.

```sh
sha256sum -c PUBLIC_MANIFEST.sha256
export CORE_LEAN=/path/to/installed/lean/bin/lean
export CORE_RUSTC=/path/to/installed/rust/bin/rustc
python3 -B rebuild/isolate.py
python3 -B rebuild/verify.py rebuild/evidence-EXAMPLE
```

Use the relative evidence directory printed by the launcher in place of `rebuild/evidence-EXAMPLE`. The final line of verification should report 15 of 15 matrix cases and 14 of 14 complete-state assertions. To compare the four compiled Lean artifacts, descriptor and signed message to the historical CORE-01C digests, copy the contents of `evidence/matched-core01c.sha256` to a trusted location or run the following from the package root after substituting the actual evidence directory.

```sh
(cd rebuild/evidence-EXAMPLE && sha256sum -c ../../evidence/matched-core01c.sha256)
```

The launcher creates a private temporary runtime under the package root and cleans it up on ordinary exit. The harness creates fresh synthetic Ed25519 keys every run. Keys, signature bytes and temporary directory names therefore vary. The receipt descriptor, signed message and Lean artifacts matched the archived CORE-01C run on the pinned tools. The public archive does not ship executable or compiled Lean files. A reproduction regenerates Lean artifacts for independent receipt-to-artifact verification.

For byte-identical packaging of the released snapshot, run `bash package.sh > ../public-review.tar.gz` from a clean extracted package and use GNU tar and gzip. Perform rebuilds in a separate extracted copy because they add new evidence. The packager normalizes entry order, timestamps, ownership and permissions.
