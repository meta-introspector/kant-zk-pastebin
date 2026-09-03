# Raw-text adapter

`RequestProject/Kant/Codec/RawText.lean`; JavaScript in `web/kant-codec.mjs`.

Raw text is a first-class input: compiler output, logs, Lean source,
stack traces, proof sketches.  The document keeps the original text, the
declared encoding, the lines, what was detected and how sure the parser
is; extraction never destroys the original.

Format detection follows the prescribed order — declared, signature,
syntax, then the raw-text fallback — and a failed parse is *not* an
invalid proof.

Proved: `joinLines_splitLines`, `detect_declared` and the per-format
detection lemmas, `importAny_sourceData` (the bytes are kept),
`importAny_status_ne_invalid` (a parse failure never becomes INVALID).
