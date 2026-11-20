# WASM compatibility

Rust stable 1.100.0 built the x86_64 Linux executable and the installed `wasm32-unknown-unknown` target offline. Node v22.23.4 instantiated the real module using its built-in WebAssembly runtime. Build logs include both Cargo dependency trees, the compiler commit and the locked crate checksums.

WASM uses pure Rust Ed25519 verification and SHA-256. It imports zero functions, including WASI, randomness, host crypto and SQLite. The loader requires a synchronous, unshared instance. Its staging region holds at most 1,052,852 bytes. The guest checks length before creating a slice. A runtime test filled linear memory to 64 pages and verified rejection of another page. Host subprocess isolation adds a five-second deadline for verifier execution.

The native CLI bounds stdin and maps input I/O errors to status 8. The WASM loader bounds stdin and maps module compilation, instantiation or call errors to status 8. The trusted host also rejects launch errors, timeouts, abnormal exits, and unexpected output.
