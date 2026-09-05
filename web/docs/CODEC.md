# The standard proof codec and exchange layer

**The codec is not the proof.**  It is the transport and reconciliation
layer that lets proofs, inputs, outputs, certificates, errors and
provenance move between systems without losing their meaning.

This document describes what is implemented and what is proved.  The Lean
modules under `RequestProject/Kant/Codec/` are the specification; every
statement below with a name in `code font` is a theorem there, checked by
`lake build` with no `sorry` and no extra axioms.  `web/kant-codec.mjs` is
an unverified JavaScript transcription pinned to the Lean side by shared
golden vectors, and `codec/` is the reference layout with the readable
schemas.

```text
                    ┌─────────────────┐
                    │  Native System  │
                    └────────┬────────┘
                      Import / Export
                             ▼
                 ┌───────────────────────┐
                 │   STANDARD CODEC      │
                 │   CANONICAL MODEL     │
                 └───────────┬───────────┘
             ┌───────────────┼────────────────┐
             ▼               ▼                ▼
           IPDL             XML          CSV / YAML
             └───────────────┼────────────────┘
                             ▼
                        Raw Text / Logs
```

## 1. No external format is canonical

The canonical model is a value tree — `Kant.Codec.Val`: null, booleans,
arbitrary-precision integers, arbitrary Unicode strings, sequences, and
mappings kept as *ordered* lists of entries so that key order and even
duplicate keys survive.  Structured, semi-structured and unstructured data
all live in it.

Every format is an adapter to and from that tree.  Nothing about XML, YAML
or CSV leaks into the model, and no format is privileged.

## 2. The canonical proof object

`Kant.Codec.Obj` has the fields the specification lists: `id`, `version`,
`kind`, `inputs`, `assumptions`, `parameters`, `procedure`,
`intermediate`, `outputs`, `claims`, `certificates`, `errors`, `warnings`,
`provenance`, `metadata`, `source_format`, `source_data`, `status`, and
`extensions`.  The required five are `id`, `kind`, `inputs`, `outputs`,
`status`; everything else may be empty.

`Obj.toVal` and `Obj.ofVal` move between the object and the value tree,
and are inverse (`Obj.ofVal_toVal`), so nothing is lost on the way in or
out.  `Obj.toVal_injective` and `Obj.eq_of_text_eq` say the canonical text
of an object determines the object.

Inputs (`Inp`) and outputs (`Outp`) carry `id`, `name`, `type`, `value`,
`encoding` and provenance, with `units` and `constraints` on inputs and
`claims` and a `certificate` on outputs.  A proof may produce several
outputs.

## 3. Statuses are not interchangeable

```text
UNKNOWN  PENDING  VALID  INVALID  PARTIAL  ERROR  CONFLICT  UNSUPPORTED
```

`Status.name` and `Status.ofName` round-trip, and `statusName_injective`
says the names are distinct — so `INVALID` cannot silently become `ERROR`.
`ERROR` means the system could not complete or interpret the operation;
`INVALID` means it completed and the result failed validation.

## 4. Errors are first-class

`Kant.Codec.Err` carries `id`, `code`, `severity` (`INFO`, `WARNING`,
`ERROR`, `FATAL`), `message`, `location`, `field`, `object_id`,
`source_system`, `source_format`, `expected`, `actual`, `cause`,
`resolution` and `recoverable`.  Errors travel with the object, are part
of its canonical encoding, and come back out of every codec unchanged.

Automatic repairs are recorded in the error that prompted them: the
`resolution` field is where `"144" → 144, string to integer coercion`
lives, and `cause` is where `schema declares integer` lives.

## 5. Deterministic serialization and content identity

`canonEnc` writes a tag character and then length-prefixed contents:
stable field order, normalised numbers, explicit nulls, explicit types,
and no escaping at all — so no character is forbidden and nothing can be
mistaken for a delimiter.

* `canonDecode_canonEnc` — it round-trips;
* `canonEnc_injective` — different values have different text;
* `valHash` / `Obj.hash` — the witness of the canonical bytes, four bytes
  per code point so the map is injective on all of Unicode.

That is what makes `CanonicalObject → CanonicalSerialize → Hash` a stable
content identity.

## 6. The five codecs

| Codec | Encoder | Round trip | Injective |
|---|---|---|---|
| Canonical | `canonEnc` | `canonDecode_canonEnc` | `canonEnc_injective` |
| YAML | `yamlEnc` | `yamlDecode_yamlEnc` | `yamlEnc_injective` |
| XML | `xmlEnc` | `xmlDecode_xmlEnc` | `xmlEnc_injective` |
| CSV | `csvEncode` | `csvDecode_csvEncode` | `csvEncode_injective` |
| IPDL | `ipdlText` | `ipdlRead_ipdlText`, `ipdl_roundTrip` | `ipdlText_injective` |
| Raw text | `rawDoc` | `joinLines_splitLines` | — |

`decodeVal_encodeVal` is the single statement that **every** codec
round-trips.

**IPDL** carries references and annotations, which the canonical model has
no constructor for.  Rather than discard them, the adapter puts them in
reserved extension keys (`$ipdl.ref`, `$ipdl.annotation`, `$ipdl.note`,
`$ipdl.body`).  `project_embed` says canonical → IPDL → canonical is the
identity; `recover_project` says IPDL → canonical → IPDL keeps references
and annotations intact.

**XML** keeps attributes, elements and text nodes distinct: a mapping
entry is an element with a `key` attribute and a child element, and the
five character entities are escaped both ways.

**CSV** is a tabular projection with the recommended columns
`object_id, object_type, field, value, value_type, parent_id`, one row per
node in preorder, a child count on every container and a parent link on
every child.  `flatRows_lossy` is the honest statement of what a *flat*
table — one without the counts and the parent links — could not represent.

**YAML** is the human-readable projection, in flow style.

**Raw text** is a first-class input.  `RawDoc` keeps the original text,
the encoding, the lines, the detected structures and a confidence, and
extraction never destroys the original.

## 7. Detection, and what a failed parse means

`detect` tries, in the prescribed order: an explicitly declared format
(`detect_declared`), then a signature, then syntax, then the raw-text
fallback.  Each format is recognised from its own output
(`detect_ipdlText`, `detect_csvEncode`, `detect_xmlEnc`,
`detect_canonEnc`, `detect_yamlEnc`).

`importAny` never treats a parse failure as a bad proof:

* `importAny_sourceData` — the original bytes are kept, always;
* `importAny_unrecognised` — unrecognised text becomes a raw object that
  still contains the text;
* `importAny_status_ne_invalid` — the resulting status is never `INVALID`.

## 8. Lossless means lossless

`declaredLossiness` declares `LOSSLESS` for each of the five target
formats, and `declared_lossless_sound` proves each really does return the
whole semantic object.  The minimal interchange profile declares only
`PARTIAL`, and `declared_partial_honest` proves it really is a projection:
two objects differing outside the profile share it (`minimal_lossy`),
while the profile's own fields round-trip (`minimal_roundTrip`).

## 9. The envelope

`Envelope` carries `schema_version`, `codec_version`, `source`,
`destination`, `timestamp`, `object_id`, `payload`, the inputs, outputs,
claims and certificates, the diagnostics, the transformation ledger and
the integrity hash.  `sealEnvelope` puts an object in, `openEnvelope`
takes it out.

* `openEnvelope_seal` — the envelope round-trips, in every format;
* `seal_integrity` — it carries the content hash of what is inside;
* `seal_ledger` — it records the conversion that produced it.

Because systems exchange envelopes rather than pairwise translations,
integrating `N` systems costs `N` adapters, not `N²`.

## 10. Import and export

`importReport` identifies the format, keeps the original, decodes, builds
the canonical object, hashes it and reports; `importReport_bytes`,
`importReport_hash` and `importReport_keeps_errors` say it does.  Nothing
malformed is discarded.

`exportReport` encodes, runs the round-trip test, records the
transformation and declares the preservation level;
`exportReport_lossiness` and `exportReport_roundTripped` say the report is
truthful, and `import_export` closes the loop.

## 11. Schema evolution

Versions are `proof-schema/MAJOR.MINOR`.  `majorMismatch_fails_safely`:
a reader that does not recognise the version refuses the envelope rather
than misreading new semantics.  `unknown_fields_preserved`: whatever the
sender put in `extensions` comes back out unchanged.  Unknown does not
mean discardable.

## 12. Validation, at four levels

`validSyntax` (does it parse?), `validStructure` (is it an object?),
`validTypes` (do the required fields have the declared types?),
`validSemantics` (does the proof engine accept it?).  The codec does not
become the proof engine — it transports what the engine needs — and
`syntax_valid_not_proof_valid` exhibits an object that passes the first
three levels and fails the fourth.

## 13. Reconciliation

Two systems decode their own native data into canonical objects, and the
comparator works on those.

* `diffVal` produces structured `Difference`s with `path`, `left`,
  `right`, `kind` and `severity` — for example
  `outputs[0].value / 42 / 43 / VALUE_MISMATCH / ERROR`;
* `diffVal_nil_iff` — the difference list is empty exactly when the two
  values are equal, so a comparison never invents or hides a disagreement;
* `compareObj` returns `EQUIVALENT`, `DIFFERENT`, `CONFLICT`,
  `INCOMPARABLE` or `INCOMPLETE`;
* `compareObj_equivalent_iff` — `EQUIVALENT` means the same object;
* `compareObj_symm` — the order of the two sides does not matter;
* `conflict_valid`, `conflict_outputs_differ` — a `CONFLICT` is only
  reported when both sides claim `VALID` and their outputs really differ.

Conflicts are never silently merged.  `resolve` takes a `Strategy`
(prefer_source, prefer_verified, prefer_newer, manual, merge, reject);
`resolve_reject` produces nothing, `merge_keeps_both` keeps both sides,
and `resolve_records` puts every resolution into the resulting object's
provenance.

## 14. Conformance

| Level | Meaning | Theorem |
|---|---|---|
| 0 | Raw — arbitrary text preserved and exchanged | `conformance_level0` |
| 1 | Structured — canonical objects imported and exported | `conformance_level1` |
| 2 | Typed — inputs, outputs, errors, statuses survive | `conformance_level2` |
| 3 | Proof-aware — settled proofs distinguished from unsettled | `conformance_level3` |
| 4 | Reconciliation — independent results compared and resolved | `conformance_level4` |
| 5 | Auditable — determinism, content identity, ledger | `conformance_level5` |

## 15. Definition of done

`definition_of_done`: one proof object, exported as IPDL, XML, CSV, YAML
or raw text, is reconstructed from each of them as the *same* canonical
object, and the comparator judges it `EQUIVALENT` to the original.
`cross_format` adds that a document exported in one format and re-exported
in another still means the same thing.

```text
             semantic(proof)
                    │
        ┌───────────┼───────────┐
        ↓           ↓           ↓
       IPDL        XML       YAML/CSV/Text
        │           │           │
        └───────────┼───────────┘
                    ↓
             Canonical Proof
                    ↓
             Same Semantics
```

## 16. Running the checks

```sh
lake build RequestProject.Kant.Codec   # the theorems and every #guard
node web/codec-test.mjs                # 91 checks of the JavaScript mirror
```

The two implementations are pinned to the same golden texts, so they are
known to agree byte for byte on the canonical, YAML, XML, CSV and IPDL
encodings of the same value, and on its content hash.
