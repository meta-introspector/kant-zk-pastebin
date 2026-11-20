# PUB01 sanitization map

Original CORE-03 archive SHA-256

`7fa1ac8e5a437e628512d3d0d944dba1cb23ad4b80176d661a8111407d5a0b7f`

All 27 original manifest entries passed. `ORIGINAL_MANIFEST.sha256` is the byte-identical original manifest, preserved at a new path. Its own SHA-256 is `38673a62ba67a6df65465735c9cac3fc17f256e087bb824c7dcf425a1a716cbf`. The historical `FINAL_REPORT.json` records the original audit and archive. `MANIFEST.sha256` covers the public derivative.

| Original path | Original SHA-256 | Public SHA-256 | Transformation |
|---|---|---|---|
| `INDEPENDENT_AUDIT.md` | `97c65aa3cbef1145afd15d2739197e0b2f007e6079e5f259ecc705d726e96992` | `7b42efbe0a77ed73b2273d1a915fedbb66cce28fe8e64af4d8fa7b59f3251e3d` | Marked as historical and updated reproduction links and regression input. |
| `SOURCE_REUSE_MATRIX.md` | `dfa442aa6cc685537e067fcb5dcf358231b23252d34814792a37fcb506d9ad97` | `75469a213bcf498e6d66bc3d49d43cafc623d5525d8f18f719112840c68705aa` | Explained the exact adapter and fixture subset and public PR dependency. |
| `evidence/audit-comparison.log` | `0870c5760786dd59a2a0f963973181b69240c3ee45e6c932361597f52b412b06` | `a3b0ad8434c50c09b15aefa74ed1dec159cf5f0b483c530ad37333f36f791ee5` | Replaced the previous JobVerifier checkout directory name with its component name. |
| `evidence/core02-independent-regression.log` | `0bf3e5dc3366fa858b8aff0577065a15bec9f8f114fa8fe4d906199127a4d6b3` | `2eb4885b723327cfe58dfe6665eb821cb89cdabcbaecd493dc9bedebdd0e5800` | Replaced local toolchain paths, dynamic linker addresses and OpenSSL thread identifier. |
| `evidence/native-wasm-independent.log` | `02521b27f329d7ede8d060a09e8b844169f3096bd7606c2d08df72f1423becd1` | `f832715d55044a7910c0c7b5c6e4250bced787e3e48c176170cc1c059d89f59e` | Replaced the absolute source path with a lab-source placeholder. |
| `evidence/native-wasm-primary.log` | `06a4ebd8ae619bbb6876693624147cea54d39f0b4cdf7e3f3cb06447d244fd13` | `fcedfefe7ecc88f7dd42da39364dfbee63779b744317747ba8ac5ecc7dab19bd` | Replaced the absolute source path with a lab-source placeholder. |
| `inputs/core02.tar.gz` | `5935eeb68abe48ff7ff41dc0c95f1a52778bb444df0f061e2c40cc56a8155b26` | Omitted | Omitted the nested archive, including previously published transcripts containing transient OpenSSL identifiers. The essential adapter and fixtures are carried byte for byte with source hashes. |
| `regress.sh` | `0b89ea0532dcf8f55146509634b48a3356e91e6da46e327f829313e3fe10713a` | `86caa6f5b166fe73d24f80b4c63e3c26b567335119d2d7a34e9b09a18fc51ac5` | Extracts and verifies the pinned CORE-02 Git subtree from public Draft PR #39 instead of the nested archive. |
| `test.py` | `4eb22fe61a8e3fd987b22d9f5bf48f13b1bb2b06c92f440f115c2386140da76c` | `80b74d88de17377a14692e273dca5d0d16613eeda472bfa9925c9b0c5095bb5f` | Loads the checked adapter and fixture subset and verifies its checksums. Vector generation, expectations and authority assertions are unchanged. |

All other original payload files retain their original bytes. The portable Rust code, WASM runner and host coordinator are unchanged.

The 12 files under `inputs/core02/` match the committed files in CORE-02 and the omitted original nested archive. The [Git blob identities](evidence/reused-core02-blobs.txt) and [subset checksums](inputs/core02.sha256) record their provenance. The nested archive had 61 files including its manifest. The full tree remains available at the pinned public PR head and is unnecessary for the portable matrix.

PUB01 adds reproduction instructions, security limitations, the rebuild report, the public manifest, this map, and fresh selected evidence for the differential, host and CORE-02 regression runs.

The retained compiled Lean fixture is synthetic proof data, pinned by the signed descriptor and inspected for embedded strings. The other binary is a 64-byte detached signature verified against the archived synthetic public key. The original outer archive shipped no native executable or WASM module. PUB01 packages neither compiled application binaries nor SQLite files or generated signing keys.

Absolute installation paths such as `/usr/bin/openssl` describe tool requirements. User-specific paths and transient runtime identifiers were removed from the public transcripts. Tar entries use numeric owner and group zero, epoch time, regular files and directories, stable modes and deterministic gzip metadata.
