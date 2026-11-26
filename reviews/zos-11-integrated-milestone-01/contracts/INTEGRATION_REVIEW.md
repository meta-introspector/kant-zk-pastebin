# Expanded request contract: integration review

The 11-05F experimental model proposes an exact
policy-bound V2 descriptor with artifact digest/size,
operation parameters, certificate and model digests,
policy digest/version, issuer key identifier, audience,
subject, replay domain, nonce and freshness.

The inherited replay tuple remains:

    (audience, subject, request_nonce)

Changes to policy or signer-key identifiers change
the descriptor digest without changing this replay key.

## Supervisor review requirements

- Distinguish untrusted descriptor types from privately
  constructed authenticated request types.
- Explicitly separate the expanded profile from older
  V2 implementations and prevent downgrade.
- Bind the subject to a stable trusted principal.
- Preserve replay identity across key rotation.
- Resolve audience aliases for shared effect stores.
- Establish operation-level idempotency across nonces.
- Reuse the qualified SQLite FFI where appropriate.
- Do not assume the proposed Rust API compiles.
- Preserve the historical receipt schema.
- Require independent policy and proof applicability.
- Preserve the existing denial-only execution boundary.

Status: experimental design review.

Real authentication and operational authorization
are not qualified.
