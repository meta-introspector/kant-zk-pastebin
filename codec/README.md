# The standard proof codec — reference layout

This directory is the specification's reference layout (§34).  It holds
the readable schemas and points at the implementations, which live where
the rest of this project lives:

* the **normative implementation** is Lean, under
  `RequestProject/Kant/Codec/`, where every claim in this directory is a
  theorem;
* the **portable implementation** is JavaScript, in `web/kant-codec.mjs`,
  pinned to the Lean side by shared golden vectors.

```text
codec/
├── schema/       proof.yaml, input.yaml, output.yaml, error.yaml, envelope.yaml
├── codecs/       ipdl/ xml/ csv/ yaml/ text/
├── canonical/    parser, serializer, validator, hasher
├── reconcile/    compare, diff, resolve
├── provenance/
└── tests/
```

| Slot | Lean | JavaScript |
|---|---|---|
| `canonical/serializer` | `Kant.Codec.canonEnc` | `canonEnc` |
| `canonical/parser` | `Kant.Codec.canonDecode` | `canonDecode` |
| `canonical/hasher` | `Kant.Codec.valHash`, `Obj.hash` | `valHash` |
| `canonical/validator` | `validSyntax`, `validStructure`, `validTypes`, `validSemantics` | — |
| `codecs/ipdl` | `Kant.Codec.Ipdl` | `ipdlText`, `ipdlRead` |
| `codecs/xml` | `Kant.Codec.Xml` | `xmlEnc`, `xmlDecode` |
| `codecs/csv` | `Kant.Codec.Csv` | `csvEncode`, `csvDecode` |
| `codecs/yaml` | `Kant.Codec.Yaml` | `yamlEnc`, `yamlDecode` |
| `codecs/text` | `Kant.Codec.RawText` | `rawDoc`, `detect` |
| `reconcile/compare` | `compareObj` | `sameValue` |
| `reconcile/diff` | `diffVal`, `Difference` | — |
| `reconcile/resolve` | `resolve`, `Strategy` | — |
| `provenance/` | `Prov`, `Trans`, `conversionRecord` | `conversionRecord` |
| `tests/` | `Kant.Codec.Tests` | `web/codec-test.mjs` |

Run the checks:

```sh
lake build RequestProject.Kant.Codec   # every `#guard` and every theorem
node web/codec-test.mjs                # the same vectors, in JavaScript
```

See `docs/CODEC.md` for the write-up.
