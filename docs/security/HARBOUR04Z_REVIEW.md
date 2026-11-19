# ZOS HARBOUR-04 — Experimental security review

**Verdict:** ACCEPT FOR EXPERIMENTAL REVIEW.

**Production acceptance:** BLOCKED.

## Scope

- `src/handlers.rs` — file-serving hardening carried forward.
- `src/gallery.rs` — experimental render-path protection.
- `src/main.rs` — explicit `UUCP_SPOOL` startup requirement.
- `src/svg_anim.rs` — experimental SVG job publication.

## Verification evidence

- HARBOUR-04R: 6/6 isolated descriptor tests passed.
- HARBOUR-04W: 5/5 isolated startup contract tests passed.
- HARBOUR-04Y: four Rust files parsed successfully.
- HARBOUR-04Z: archive integrity and evidence inventory passed.

These isolated checks do not prove that the integrated
application compiles or runs.

## Blocking limitations

1. Full Cargo compilation is blocked by the private `nora`
   registry configuration.
2. Integrated Actix handler type-checking remains unverified.
3. `svg2anim-worker` compatibility has not been established.
4. Spool root and parent-directory trust remain unverified.
5. Renaming directories after opening their descriptors may
   make published jobs invisible to path-based consumers.
6. Post-publication failure semantics, staging crash recovery
   and full regression coverage remain unresolved.
7. The experimental implementation has Linux x86_64
   portability constraints.

## Deployment restrictions

- Do not merge or deploy without further review.
- Do not enable the seven disabled tiles or eight operations.
- Require explicit review of `UUCP_SPOOL` deployment settings.

## Sealed review bundle

Filename: `HARBOUR04Z_REVIEW.tar.gz`

SHA-256:
`c50ff50d3411bf1a6681e3d9b4e876e1c6861bc9d5be9da61635bc0893f56252`

The bundle is an evidence artifact, not included in this commit.
