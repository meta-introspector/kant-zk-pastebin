# Running the Rust tests

`cargo test` in this repository aborts before `main` with

```
*** stack smashing detected ***: terminated
```

and no test output. It is not a test failure and not a property of the tree —
it happens identically on a clean checkout. The cause is the environment: the
binary is linked against a Nix toolchain, so it is started by the Nix loader
`/nix/store/…-glibc-2.42-61/lib/ld-linux-x86-64.so.2`, but `libc.so.6` still
resolves to `/usr/lib/x86_64-linux-gnu/libc.so.6`. A loader and a libc that
disagree about the process layout will corrupt the stack during startup.

`gdb` confirms it — the crash is inside libc, before any Rust frame exists:

```
Program received signal SIGABRT, Aborted.
#0  0x00007ffff7c969bc in ?? ()      # libc, not the binary
#1  0x0000000000000000 in ?? ()
```

## Running them

Two things have to be right.

**1. Point the build at a Nix OpenSSL.** Without it the `openssl-sys` build
script fails with "Failed to find OpenSSL development headers":

```sh
export OPENSSL_DIR=/nix/store/<…>-openssl-3.6.2-dev
export OPENSSL_LIB_DIR=/nix/store/<…>-openssl-3.6.2/lib
export PKG_CONFIG_PATH=$OPENSSL_DIR/lib/pkgconfig
```

`nix develop` supplies all three; the flake's devShell has `openssl.dev` and
`pkg-config`.

**2. Put the matching glibc on `LD_LIBRARY_PATH`:**

```sh
cargo test --offline --lib --no-run      # build, then run it directly

BIN=$(ls -t target/debug/deps/kant_pastebin-* | grep -v '\.d$' | head -1)
LD_LIBRARY_PATH=/nix/store/<…>-glibc-2.42-61/lib "$BIN" --test-threads=1
```

Do **not** wrap that last line in `timeout` (or any other system binary).
`LD_LIBRARY_PATH` applies to the whole process, so the wrapper resolves against
the Nix glibc too and dies before it can exec anything:

```
timeout: symbol lookup error: …/glibc-2.42-61/lib/libc.so.6:
  undefined symbol: __tunable_is_initialized, version GLIBC_PRIVATE
```

That error names `timeout`, not the test binary, so it reads like a broken
environment rather than a mistake in the invocation. Build with a timeout,
run without one.

`--test-threads=1` is not required by the code; it just keeps the output
readable when a failure does happen.

Note that `cargo test -- --list` also crashes before the fix, which is the
quickest way to tell this apart from a genuine failure in a test.

## What is green

75 tests, `75 passed; 0 failed` (as of `f360e985`):

| module | tests |
|---|---|
| `libp2p_frames` | 27 — wire format, byte-identical to `web/kant-libp2p.mjs` |
| `libp2p_transport` | 15 — gossipsub topics, nonce, serve, reassembly |
| `mesh` | 4 — the `MeshState` storage proxies, shared vs isolated storage, avatar filtering |
| `ipfs` | 3 — a failed block write yields no CID |
| `handlers` | 5 |
| `plugins::git2nora`, `plugins::pipelight` | 13 |
| `git_mount`, `rename`, `share` | 5 |

The 42 `libp2p_*` tests run in this crate. An earlier revision of this file said
the harness made that impossible; it is not. `scripts/frames-crosscheck.sh` also
decodes real JS frames with the Rust code and re-encodes them, so the two
implementations are checked against each other and not only against themselves.

The four `mesh` tests and three `ipfs` tests came from PRs #5 and #1; the
branch had no coverage of either before.

## Why `--offline`

The crate depends on `erdfa-publish` from a private registry (`nora`) plus
`dlasl`-adjacent crates. With network access cargo tries to re-resolve and
fails on credentials. `--offline` against a populated `~/.cargo/registry`
works; `cargo metadata --offline` first is a cheap way to check.
