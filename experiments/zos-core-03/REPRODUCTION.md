# Reproduce the public review

Use Linux x86-64 and a fresh isolated lab. This review used Rust stable 1.100.0 with the installed `wasm32-unknown-unknown` target, Node.js 22.23.4, Python 3.14, OpenSSL 3.5.5, SQLite 3.46.1 with development linker support, and GNU coreutils, tar and gzip. The exact crate versions and checksums are in `Cargo.lock`. Put them in the local Cargo cache before starting. The build uses Cargo offline and locked.

From the extracted archive:

```sh
sha256sum -c MANIFEST.sha256
bash build.sh /absolute/lab/fresh-build
bash build.sh /absolute/lab/independent-build
```

Each run builds the native verifier and a real import-free WebAssembly module, regenerates the same 24 framed vectors, and executes both runtimes against each vector. It builds the bundled byte-identical CORE-02 adapter with the pinned archived fixture key and exercises the authority boundary against fresh synthetic databases. The verifier, adapter source, and all receipt and Lean fixtures needed for this run are in the public package. Test outputs and generated synthetic signing keys stay in the chosen build directory.

To replay the full historical CORE-02 regression, use a local Git checkout that contains the published PR #39 head `502827ec3db0186b681008f419a7942fd524dce8`. The script verifies the Git subtree and package manifest, then rebuilds and runs CORE-02 with installed Lean 4.35.0 and Rust 1.97.1. This extra replay requires Linux x86-64 with Landlock ABI 5 or later.

```sh
CORE_LEAN=/absolute/toolchains/lean/bin/lean \
CORE_RUSTC=/absolute/toolchains/rust/bin/rustc \
  bash regress.sh /absolute/lab/fresh-core02-regression /absolute/repo-with-pr39
```

Repack the untouched public source tree with `bash package.sh /absolute/lab/repacked.tar.gz`. Compare it with the distributed archive or verify the external SHA-256 sidecar. [Published CORE-02 draft PR](https://github.com/meta-introspector/kant-zk-pastebin/pull/39)
