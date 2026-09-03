# The required test suite

The specification's list (§33) is run in both implementations:

* Lean — `RequestProject/Kant/Codec/Tests.lean`, checked at compile time
  with `#guard`: empty object, minimal object, nested object, multiple
  inputs, multiple outputs, missing field, unknown field, invalid type,
  malformed input, Unicode, large numbers, null values, duplicate
  identifiers, references, errors, warnings, partial proofs, failed
  proofs, successful proofs, round-trip conversion, lossy conversion —
  and the proof-specific cases: a known valid proof, a known invalid
  proof, a known contradictory pair, a known incomplete proof and a known
  incompatible output.
* JavaScript — `web/codec-test.mjs`, run with `node web/codec-test.mjs`.

Both are pinned to the same golden texts, so the two implementations are
known to agree byte for byte on the canonical, YAML, XML, CSV and IPDL
encodings of the same value, and on its content hash.
