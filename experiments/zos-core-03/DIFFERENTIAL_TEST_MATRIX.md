# Differential test matrix

The harness sends each framed vector byte for byte to the native stdin adapter and a real WASM instance. Both must return the listed status. Logs record SHA-256 for every vector and the independent rebuild compares all result lines.

| Scope | Cases | Expected |
|---|---|---|
| Shared | Deterministic valid receipt and archived Lean issuer receipt | 1 |
| Shared | Missing fields, truncated length/value/signature/key, trailing byte | 2 |
| Shared | Oversized declared length, message, artifact and entire frame | 3 |
| Shared | Invalid signature and wrong valid public key | 4 |
| Shared | Authentically signed descriptor tampering, signed operation substitution, duplicate field, CRLF, invalid UTF-8, unknown signed verdict | 5 |
| Shared | Wrong artifact and changed artifact at the exact one-MiB bound | 6 |
| Shared | Requested operation substitution and unauthorized operation | 7 |
| WASM only | Overlength direct ABI call, zero imports, exact memory growth cap | Rejection or required invariant |
| WASM only | Corrupt module load | 8 |
| Native only | Independent CORE-02 OpenSSL and SQLite authority, including all original regression scenarios | Original contract |
| Trusted host | Unknown guest code, indeterminate or missing verifier, timeout, unauthorized principal or operation, invalid signature and simulated forged success | Reject and retain zero receipt/effect rows and balance 100 |
| Trusted host | Valid WASM receipt, repeated through WASM and native verification | One debit, one audit row, balance 93, replay on each repeat |
| Trusted host | Separate control database | Byte-identical |

Run `bash build.sh /absolute/path/to/fresh-output` for the shared, WASM and host matrix.
