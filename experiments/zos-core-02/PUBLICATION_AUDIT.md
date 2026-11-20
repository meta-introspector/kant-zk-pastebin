# Publication audit

The original archive SHA-256 was verified as `155fc65b812f11174c7d6fd1ebfccaa876c2a068e457a04713b39a11dbc7eefd`. All 58 original payload hashes passed. The exact original manifest is preserved in `ORIGINAL_MANIFEST.sha256`.

We reviewed the source, launch and test scripts, transcripts and archive headers. The two PEMs are synthetic public keys. The 64-byte binary is a detached Ed25519 signature for the archived synthetic receipt. The archive contains no private key files, credentials, database snapshots, executables, or compiled Lean files. Standard tool paths and reproduction placeholders remain public. File metadata is normalized to numeric owner/group 0 and epoch timestamps.

Two files had local experiment instance suffixes replaced with `<instance>`. The source reuse report also describes the masking. The hash values and test events remain intact. Historical executable test logs, fixtures and the signature are byte-identical. This derivative adds the original manifest and this audit, regenerates the top-level manifest and omits no original payload files.

| Transformed file | Original SHA-256 | Public SHA-256 |
|---|---|---|
| `SOURCE_REUSE_MATRIX.md` | `30519f35007d96d30359ca48052485af3bcb6cc86a5eee9a8bd5c906561d6437` | `f4eeef64471b293a00426577c290ad7e8333dd0ef2d04f698e54faf0cfcc24e6` |
| `evidence/source-identity.log` | `1d2c26a91df7c9836d3e8291cd9626105329b75ef45bc4e73dd50972b4e59b97` | `fbc8a7af25922a8e69a5af972e6a4df4c8b2494942690df7e06ee5b2644049af` |

The public reproduction rebuilds the packaged fixture and checks it against the pinned blobs and artifact digests. It uses installed tools and regenerates the synthetic signing identity. The prior local experiment directories are provenance only and are unnecessary for reproduction.

Physical power-loss recovery, external replay anchoring, issuer compromise and production deployment remain outside the verified scope. Production acceptance remains BLOCKED. The historical REUSE-04R-06 service rerun remains blocked and excluded from the experimental verdict.
