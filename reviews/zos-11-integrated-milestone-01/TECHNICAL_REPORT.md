# ZOS-11 — Integrated Experimental Milestone 01

Date: 2026-11-26

Status: Experimental technical review.
Not production-ready.

## Executive summary

The project has advanced from separately qualified
components toward an integrated artifact retrieval
and execution-authority boundary.

The latest experiment successfully retrieved a
synthetic WebAssembly artifact through real offline
Kubo, using the previously qualified Rust integrity
gate and bounded consumer.

The accepted bytes were independently verified by
a non-test Rust consumer using the unchanged private
execution library.

The artifact was correctly denied execution because
it did not match the historical authority fixture.

This demonstrates an integrated denial path, not an
authorized operational execution path.

## Experimental evidence

| Component | Result |
|---|---|
| Wasmi runtime regressions | 58/58 |
| Historical authority composition | 8/8 |
| Private execution boundary | 8/8 |
| External API visibility | 9/9 |
| Non-test external Rust consumer | 9/9 |
| Canonical encoding vectors | 7/7 |
| Independent replay model | 17/17 |
| Sealed Kubo runtime identities | 13/13 |
| Kubo provider checks | 9/9 |
| Kubo-to-Rust integration | 6/6 |
| Latest integration manifest | 509/509 |

These suites overlap and do not represent independent
security properties or a comprehensive security proof.

## Expanded authenticated request research

The parallel 11-05F research stage reported:

- Expanded contract model: 37/37.
- Inherited replay model: 17/17.
- Inherited Rust suite: 43/43 serialized.
- Inherited Rust suite: 43/43 parallel.
- Private archive manifest: 587/587.

Ubuntu independently verified the archive integrity
and recovered the contract documents.

Ubuntu has not yet independently reproduced the
expanded model or compiled its proposed Rust API.

No signature was created or verified by 11-05F.

## Safety architecture

Artifact integrity, caller authentication, formal
proof validity, proof applicability, policy evaluation,
replay state, execution authority, receipts and DAO
accounting are separate trust boundaries.

Integrity does not imply authorization.

The latest Kubo integration did not invoke Lean for
the new fixture because structural artifact binding
failed before that stage.

## Resource isolation

The latest Kubo provider phase used sealed runtime
files and Bubblewrap isolation with a dedicated
systemd service configured for bounded resources.

The Rust phase used a separate bounded sandbox.

Reported service runtimes:

- Kubo provider: 2.276 seconds.
- Rust phase, including build: 18.593 seconds.

Reported peak memory:

- Kubo provider: 405.3 MiB.
- Rust phase: 750.6 MiB.

No strict end-to-end latency guarantee is established.

## Source distribution

The full private research inventory contains 65
verified technical files.

This package publishes selected evidence, technical
documentation, provenance hashes and an independent
evidence-verification utility.

Recovered implementation sources, third-party
binaries, private databases and private runtime
repositories are excluded.

The package is not a complete standalone source
distribution or independently rebuildable ZOS runtime.

## Next engineering objectives

- Reconcile expanded request identity.
- Verify cross-language canonical encoding.
- Qualify actual caller authentication.
- Establish proof-to-artifact applicability.
- Bind independent policy evaluation.
- Establish durable authorization and effect semantics.
- Qualify a separately controlled positive execution
  path before considering operational activation.

## Final status

REAL_ACTION_AUTHORIZATION=DISABLED
DAO_CREDITS_AUTHORIZED=NO
PRODUCTION_ACCEPTANCE=BLOCKED
