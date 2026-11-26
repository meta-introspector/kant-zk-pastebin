# Evidence verification and reproduction scope

## Package integrity

From the extracted package directory:

    sha256sum --strict -c SHA256SUMS

The public manifest covers the package payload,
excluding the manifest itself.

## Synthetic fixture

The artifact under evidence/fixture.wasm contains
36 bytes of inert synthetic WebAssembly.

Its expected SHA-256 and CID are recorded in
evidence/FIXTURE_DESCRIPTOR.json.

Verify the artifact without executing it:

    sha256sum evidence/fixture.wasm
    wc -c evidence/fixture.wasm

## Qualification scope

The package currently provides selected experimental
evidence, integration contracts and architecture.

It is not yet a complete standalone source distribution.

The original laboratories used Ubuntu WSL2, isolated
Kubo repositories, Bubblewrap, systemd cgroups, Rust
and pinned Lean toolchains.

The complete rebuild requires eligible source code,
qualified dependency versions, exact fixture inputs
and runtime installation instructions.

A successful manifest verification is not an
independent reproduction of experimental results.

## Standalone evidence verifier

With Python 3 installed, run:

    python3 -I -B tools/verify_evidence.py

This verifies complete package manifest coverage,
fixture size, SHA-256, raw CIDv1 and selected
consistency properties of the reported results.

It does not execute the original test suites.
No additional Python packages are required.
