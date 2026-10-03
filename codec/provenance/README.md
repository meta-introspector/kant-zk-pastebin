# Provenance and the transformation ledger

`Kant.Codec.Prov` and `Kant.Codec.Trans` in
`RequestProject/Kant/Codec/Model.lean`, with `conversionRecord`,
`sealEnvelope` and `exportReport` in `Exchange.lean`.

Every transformed object retains where it came from — source system,
source file, source format, when it was imported and transformed, the
transformations applied, and its parent object — so a YAML document
produced from Lean output through a parser can still name the Lean output
it came from.

Every conversion appends a ledger entry recording the operation, the two
formats, the input and output hashes, the codec and its version, the
declared lossiness, and any errors or warnings.  `seal_ledger` and
`exportReport_lossiness` are the statements that this really happens.
