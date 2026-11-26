# Security boundaries and experimental limitations

## Trust separation

The following properties must remain independent:

1. Artifact integrity.
2. Caller authentication.
3. Formal proof validity.
4. Proof applicability to an artifact and operation.
5. Policy identity and policy evaluation.
6. Replay uniqueness.
7. Operational execution authorization.
8. Receipt issuance.
9. Accounting and DAO authorization.

None may be inferred solely from another.

## Demonstrated negative properties

The latest integrated experiment rejects incorrect
digests, incorrect sizes and invalid CIDs.

The Rust consumer rejects altered, truncated,
oversized and empty artifact buffers.

An integrity-verified artifact without applicable
execution authority is denied.

The original execution library remains unchanged.

## Unresolved properties

- Authentic expanded-V2 signature verification.
- Issuer registry, rotation and revocation.
- Expanded Rust/Python canonical-byte equality.
- General proof-to-artifact applicability.
- Trusted policy decision attestation.
- Semantic operation deduplication across nonces.
- Audience alias configuration.
- Durable combined authorization/effect transactions.
- External anti-rollback protection.
- Complete runtime closure.
- Strict end-to-end deadline.
- Cross-process immutable transfer.
- Positive operational execution authorization.
- Production deployment security.

## Publication scope

An experimental review package does not constitute
production acceptance, a security certification,
or permission to execute untrusted code.

REAL_ACTION_AUTHORIZATION=DISABLED
DAO_CREDITS_AUTHORIZED=NO
PRODUCTION_ACCEPTANCE=BLOCKED
