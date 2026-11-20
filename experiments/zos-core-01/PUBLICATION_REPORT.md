# CORE-01C public-review archive

**Publication verdict: SAFE_FOR_PUBLIC_IPFS_REVIEW. Production acceptance: BLOCKED.**

This is a derivative of the CORE-01C handoff, whose archive SHA-256 is recorded in the sanitization map. The historical report is a derived copy of the original report. The files under `evidence/` record a new run from the portable sources.

The sanitized offline rebuild compiled the Rust adapter and four Lean fixtures. All 15 executable cases passed, zero failed, and zero were skipped. All 14 rejection cases checked the expected denial and preserved complete synthetic DAO state. These include artifact and descriptor substitution, authorization, replay, and operation substitution. OpenSSL independently verified the exported Ed25519 receipt under the pinned synthetic public key and rejected the alternate public key. The four Lean artifacts, descriptor and signed message were byte-identical to the original CORE-01C exports.

The original adapter executable is omitted. The new Rust executable ran in the private temporary runtime and was removed with it. The public evidence keeps the normalized command transcript, adversarial test output, descriptor, signed message, signature and public keys. Compiled Lean files stay outside the publication package. The public build uses explicitly configured Lean and Rust executable paths and checks the pinned Lean digest and Rust commit. This tightens the historical version-based launcher checks. The experiment's proof, descriptor and DAO acceptance behavior stayed the same in the full rerun.

The first adaptation attempt caught an extra delimiter at Rust compilation. The corrected source passed the full rebuild and matrix. The unsuccessful attempt's diagnostic artifacts are outside the public package.

The release includes a per-file provenance map and a SHA-256 manifest. No publication was performed.
