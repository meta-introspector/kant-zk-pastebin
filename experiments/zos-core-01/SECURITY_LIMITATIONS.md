# Security limitations

Derived from the original CORE-01C security gaps, adapter design and final report. Production acceptance remains **BLOCKED**.

- The experiment assumes a trusted launcher, local tools and Lean sysroot. Version and digest checks cover selected inputs. Dependency attestation is outside scope.
- The experiment covers one pinned, source-compiled proof fixture. Arbitrary Lean intake and separate kernel replay of external compiled artifacts are outside scope.
- Before-and-after file hashes do not protect against concurrent same-UID substitution. Landlock constrains writes and TCP access for the build. Production sandboxing is outside scope.
- Replay state is in memory. The matrix covers a synthetic DAO. Real wallets, live governance, ledger operations and WASM are outside scope.
- Each run generates synthetic signing keys. Normal cleanup removes them. A crash or forced kill can leave the private runtime directory. The runner refuses to continue while that directory exists.
