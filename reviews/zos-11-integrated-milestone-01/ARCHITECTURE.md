# ZOS experimental architecture

## Target architecture

Authenticated request
  -> canonical identity and trusted policy context
  -> Kubo/IPFS retrieval
  -> sealed integrity gate
  -> bounded transport
  -> immutable verified artifact
  -> independent Lean verification
  -> independent policy evaluation
  -> private Wasmi execution boundary
  -> durable receipt and replay transaction
  -> SQLite accounting
  -> SolFunMeme DAO governance

This is a target architecture, not a fully qualified
operational pipeline.

## Demonstrated integration

Real offline Kubo retrieval
  -> sealed Rust integrity gate
  -> bounded Python consumer
  -> reverified inter-process file handoff
  -> immutable verified Rust artifact
  -> execution authority rejection.

The latest 36-byte synthetic WASM fixture was rejected
at the historical artifact-binding boundary.

No Lean subprocess was observed for that fixture.

The positive execution path remains disabled.

## Existing experimental components

- Wasmi resource-constrained runtime.
- Real Lean GOAP certificate verification.
- Independent Lean policy evaluation.
- Historical Lean JobVerifier.
- Private Rust artifact and execution boundary.
- Canonical request identity model.
- Durable SQLite replay and receipt experiments.
- Offline Kubo integrity-gated retrieval.

These components have different qualification scopes.

## Proposed authenticated request contract

The expanded 11-05F model preserves the inherited
replay key:

    (audience, subject, request_nonce)

The complete canonical descriptor digest additionally
binds artifact, operation, certificate, model, signer
key identifier, policy identity and freshness.

The expanded contract has not yet been integrated
with the qualified Rust execution boundary.

## Governance

SolFunMeme governance and service-credit accounting
remain future operational integration targets.

No final token-economic rules are established by
these experiments.
