# Task: pastebin-cargo-test-glibc-loader

**Status:** open
**Project:** kant/pastebin
**Found:** 2026-10-02 — this is why the repo has 22 Rust tests nobody has ever run

## Problem

`cargo test` aborts before `main`:

```
*** stack smashing detected ***: terminated
```

with no test output, on a clean checkout, on every branch. It is not the tree.
gdb shows the crash is inside libc with no Rust frame above it, and
`info proc mappings` shows why:

```
0x7ffff7fc4000  ld-linux-x86-64.so.2   /nix/store/fjkx1l5…-glibc-2.42-61/lib/…
0x7ffff7c28000  libc.so.6              /usr/lib/x86_64-linux-gnu/libc.so.6
```

A Nix loader starting a process against the host `/usr` libc. They disagree
about process layout, so the stack is corrupted during startup.

The workaround works and runs all 29 tests:

```sh
LD_LIBRARY_PATH=/nix/store/57iz36553175g3178pvxjij8z5rcsd4n-glibc-2.42-61/lib \
  ./target/debug/deps/kant_pastebin-<hash> --test-threads=1
```

## Fix

Make it impossible to hit by accident:

* put the loader and the glibc in the flake devShell's environment (or wrap
  `cargo test` in a shell app) so `nix develop -c cargo test` just works;
* add a `make test-rust` that does the above;
* `docs/RUST_TESTS.md` already records the manual recipe — reference it from
  the devShell rather than leaving it as tribal knowledge.

Note the build also needs `OPENSSL_DIR` pointed at a nix openssl, or
`openssl-sys` fails with "Failed to find OpenSSL development headers"; and
`--offline`, because the crate pulls from the private `nora` registry.

## Verify

```sh
cd /mnt/data1/kant/pastebin-cli-fileshare
nix develop -c cargo test --offline --lib    # want 29 passed, no LD_LIBRARY_PATH
```
