# The canonical layer

`RequestProject/Kant/Codec/Val.lean` and `Model.lean`.

* **serializer** — `canonEnc`: a tag character then length-prefixed
  contents.  Stable field order, normalised numbers, explicit nulls,
  explicit types, deterministic arrays.  Nothing is escaped, so no
  character is forbidden and nothing can be mistaken for a delimiter.
* **parser** — `canonDecode`, with `canonDecode_canonEnc` and
  `canonEnc_injective`.
* **hasher** — `valHash` / `Obj.hash`: the witness of the canonical bytes,
  four bytes per code point so the map is injective on all of Unicode.
  Equal objects hash equally; equal canonical text means equal object.
* **validator** — the four levels: `validSyntax`, `validStructure`,
  `validTypes`, `validSemantics`, and `syntax_valid_not_proof_valid`,
  which says a syntactically valid object is not thereby a valid proof.
