/-
# Emission: one domain, five representations

Every representation is a projection of the canonical domain graph, and
every projection comes back.

```text
IPDL  ─┐
XML   ─┤
CSV   ─┼──> Canonical Domain
YAML  ─┤
TEXT  ─┘
```

`emit` writes a domain in a format; `parse` reads it back.  `parse_emit`
says the graph survives, `cross_representation` says all five decode to
the *same* graph, and `hash_shared` says every file carries the same
canonical hash — so two files in different formats can be shown to be the
same underlying domain.

The raw-text form is not second class.  `emitText` writes the readable
rendering of §13 — domain, objects, claims, proofs, inputs, outputs,
relationships, diagnostics, provenance — in an envelope that also carries
the canonical block, so the text file a person reads is the text file a
machine decodes back into the graph, exactly.

Emission may also be partitioned into `objects`, `proofs`, `relations`
and the domain header; `partition_recovers` says the partition can be put
back together into the domain it came from.
-/
import Mathlib
import RequestProject.Kant.Codec.Exchange
import RequestProject.Kant.Domain.Model

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.Dom

open Kant.Codec

/-! ## The readable rendering -/

/-- Lines joined with newlines. -/
def joinL : List (List Char) → List Char
  | [] => []
  | [l] => l
  | l :: ls => l ++ '\n' :: joinL ls

/-- `KEY: value`. -/
def kv (k v : List Char) : List Char := k ++ ": ".toList ++ v

/-- A list of identifiers as an indented block, or `-` when empty. -/
def idBlock (xs : List Id) : List Char :=
  match xs with
  | [] => "  -".toList
  | _ => joinL (xs.map fun x => "  ".toList ++ x)

/-- One domain object, rendered. -/
def DomObj.report (o : DomObj) : List Char :=
  joinL [kv "OBJECT".toList o.id, kv "TYPE".toList o.kind, kv "NAME".toList o.name,
         kv "STATUS".toList o.truth.name, kv "HASH".toList o.hash,
         "CLAIM:".toList, "  ".toList ++ o.claim,
         "INPUTS:".toList, idBlock o.inputs,
         "OUTPUTS:".toList, idBlock o.outputs,
         "PROVEN BY:".toList, idBlock o.proofRefs,
         "EVIDENCE:".toList, idBlock o.evidenceRefs,
         "ERRORS:".toList, idBlock o.errorRefs]

/-- One proof record, rendered. -/
def ProofRec.report (p : ProofRec) : List Char :=
  joinL [kv "PROOF".toList p.id, kv "NAME".toList p.name, kv "KIND".toList p.kind,
         kv "STATUS".toList p.status.name,
         kv "SOURCE".toList (p.sourceFile ++ ":".toList ++ p.sourceLoc),
         kv "CERTIFICATE".toList
           (match p.certificate with
            | none => "-".toList
            | some c => c.kind ++ " ".toList ++ c.digest ++ " ".toList ++ c.evidence.name),
         "INPUTS:".toList, idBlock p.inputRefs,
         "OUTPUTS:".toList, idBlock p.outputRefs,
         "ESTABLISHES:".toList, idBlock p.claimRefs,
         "DEPENDS ON:".toList, idBlock p.dependsOn]

/-- One relation, rendered. -/
def Relation.report (r : Relation) : List Char :=
  r.source ++ " ".toList ++ r.kind.name ++ " ".toList ++ r.target

/-- One claim, rendered. -/
def Claim.report (c : Claim) : List Char :=
  joinL [kv "CLAIM".toList c.id, kv "ABOUT".toList c.objectRef,
         kv "STATUS".toList c.truth.name, "TEXT:".toList, "  ".toList ++ c.text,
         "PROVEN BY:".toList, idBlock c.proofRefs]

/-- The whole domain, rendered as raw text: description, objects, claims,
proofs, inputs, outputs, relationships, diagnostics, provenance. -/
def Domain.report (d : Domain) : List Char :=
  joinL ([kv "DOMAIN".toList d.id, kv "NAME".toList d.name, kv "VERSION".toList d.version,
          kv "HASH".toList d.hash, "DESCRIPTION:".toList, "  ".toList ++ d.description, "".toList]
         ++ d.objects.map DomObj.report
         ++ d.claims.map Claim.report
         ++ d.proofs.map ProofRec.report
         ++ ["RELATIONS:".toList] ++ d.relations.map (fun r => "  ".toList ++ r.report)
         ++ ["DIAGNOSTICS:".toList]
         ++ d.errors.map (fun e => "  ".toList ++ e.code ++ " ".toList ++ e.message)
         ++ ["PROVENANCE:".toList]
         ++ d.provenance.map (fun p => "  ".toList ++ p.sourceSystem ++ " ".toList ++ p.sourceFile))

/-! ## The text envelope

The readable rendering is written first, length-prefixed, and the
canonical block follows it, so a reader gets the text and a decoder gets
the graph — from the same file, with no ambiguity and no escaping. -/

/-- The banner every domain text file starts with. -/
def textHeader : List Char := "KANT-DOMAIN-TEXT/1.0\n".toList

/-- A domain as raw text: banner, readable rendering, canonical block. -/
def emitText (d : Domain) : List Char :=
  textHeader ++ encStr (Domain.report d) ++ canonEnc d.toVal

/-- The readable rendering and the graph, read back out of a text file. -/
def parseTextFull (s : List Char) : Option (List Char × Domain) :=
  if textHeader.isPrefixOf s then
    match readStr (s.drop textHeader.length) with
    | some (readable, rest) => (canonDecode rest).bind (fun v => (Domain.ofVal v).map (readable, ·))
    | none => none
  else none

/-- The graph, read back out of a text file. -/
def parseText (s : List Char) : Option Domain := (parseTextFull s).map Prod.snd

/-- **The raw-text form carries the whole graph and the whole readable
rendering**, and both come back out of it. -/
theorem parseTextFull_emitText (d : Domain) :
    parseTextFull (emitText d) = some (Domain.report d, d) := by
  have hpre : textHeader.isPrefixOf (emitText d) = true := by
    simp [emitText, textHeader, List.isPrefixOf_iff_prefix]
  have hdrop : (emitText d).drop textHeader.length
      = encStr (Domain.report d) ++ canonEnc d.toVal := by
    simp [emitText]
  simp only [parseTextFull, hpre, if_pos, hdrop, readStr_encStr, canonDecode_canonEnc,
    Option.bind_some, Domain.ofVal_toVal, Option.map_some]

/-! ## The five formats -/

/-- A domain written in a format. -/
def emit : Fmt → Domain → List Char
  | .text, d => emitText d
  | f, d => encodeVal f d.toVal

/-- A domain read back from a format. -/
def parse : Fmt → List Char → Option Domain
  | .text, s => parseText s
  | f, s => (decodeVal f s).bind Domain.ofVal

/-- **Every representation round-trips**: the graph that goes into a file
is the graph that comes out of it. -/
@[simp] theorem parse_emit (f : Fmt) (d : Domain) : parse f (emit f d) = some d := by
  cases f with
  | text =>
      simp [emit, parse, parseText, parseTextFull_emitText]
  | _ => simp [emit, parse, decodeVal_encodeVal]

/-- **All representations describe the same graph.**  `decode(IPDL) =
decode(XML) = decode(CSV) = decode(YAML) = decode(TEXT)`. -/
theorem cross_representation (f g : Fmt) (d : Domain) :
    parse f (emit f d) = parse g (emit g d) := by
  rw [parse_emit, parse_emit]

/-- **Every representation carries the same canonical hash**, so files
that look nothing alike can be shown to be the same domain. -/
theorem hash_shared (f : Fmt) (d : Domain) :
    (parse f (emit f d)).map Domain.hash = some d.hash := by
  rw [parse_emit]; rfl

/-- **The canonical text is recoverable from any representation.** -/
theorem text_shared (f : Fmt) (d : Domain) :
    (parse f (emit f d)).map Domain.text = some d.text := by
  rw [parse_emit]; rfl

/-- Two files, in whatever formats, hold the same domain exactly when
their decoded graphs agree — and then they carry the same hash. -/
theorem same_domain_iff (f g : Fmt) (a b : Domain) :
    parse f (emit f a) = parse g (emit g b) ↔ a = b := by
  constructor
  · intro h
    rw [parse_emit, parse_emit] at h
    exact Option.some.inj h
  · intro h; rw [h, parse_emit, parse_emit]

/-! ## Partitioned emission -/

/-- The domain header: everything except the three big tables. -/
def metaVal (d : Domain) : Val :=
  .obj [("id".toList, .str d.id), ("name".toList, .str d.name),
        ("version".toList, .str d.version), ("description".toList, .str d.description),
        ("claims".toList, .list (d.claims.map Claim.toVal)),
        ("evidence".toList, .list (d.evidence.map Evidence.toVal)),
        ("schemas".toList, .list (d.schemas.map Schema.toVal)),
        ("errors".toList, .list (d.errors.map Err.toVal)),
        ("provenance".toList, .list (d.provenance.map Prov.toVal))]

/-- The objects table. -/
def objectsVal (d : Domain) : Val := .list (d.objects.map DomObj.toVal)

/-- The proof catalog. -/
def proofsVal (d : Domain) : Val := .list (d.proofs.map ProofRec.toVal)

/-- The relations table. -/
def relationsVal (d : Domain) : Val := .list (d.relations.map Relation.toVal)

/-- The partition put back together. -/
def recombine : Val → Val → Val → Val → Option Domain
  | .obj fs, .list os, .list ps, .list rs => do
      let id ← getStr fs "id".toList
      let name ← getStr fs "name".toList
      let version ← getStr fs "version".toList
      let description ← getStr fs "description".toList
      let claims ← (getList fs "claims".toList).bind (listOf Claim.ofVal)
      let evidence ← (getList fs "evidence".toList).bind (listOf Evidence.ofVal)
      let schemas ← (getList fs "schemas".toList).bind (listOf Schema.ofVal)
      let errors ← (getList fs "errors".toList).bind (listOf Err.ofVal)
      let provenance ← (getList fs "provenance".toList).bind (listOf Prov.ofVal)
      let objects ← listOf DomObj.ofVal os
      let proofs ← listOf ProofRec.ofVal ps
      let relations ← listOf Relation.ofVal rs
      pure { id, name, version, description, objects, relations, proofs, claims, evidence,
             schemas, errors, provenance }
  | _, _, _, _ => none

/-- **A partitioned package is the domain it was cut from.** -/
theorem recombine_parts (d : Domain) :
    recombine (metaVal d) (objectsVal d) (proofsVal d) (relationsVal d) = some d := by
  cases d
  simp +decide [recombine, metaVal, objectsVal, proofsVal, relationsVal, getStr, getList,
    lookupF, listOf_map DomObj.ofVal_toVal, listOf_map Relation.ofVal_toVal,
    listOf_map ProofRec.ofVal_toVal, listOf_map Claim.ofVal_toVal,
    listOf_map Evidence.ofVal_toVal, listOf_map Schema.ofVal_toVal,
    listOf_map Err.ofVal_toVal, listOf_map Prov.ofVal_toVal]

/-- **Partitioned emission recovers the whole domain**, in every format:
write `objects`, `proofs`, `relations` and the header as separate files,
read the four back, and the graph is the one you started with. -/
theorem partition_recovers (f : Fmt) (d : Domain) :
    (do
      let m ← decodeVal f (encodeVal f (metaVal d))
      let o ← decodeVal f (encodeVal f (objectsVal d))
      let p ← decodeVal f (encodeVal f (proofsVal d))
      let r ← decodeVal f (encodeVal f (relationsVal d))
      recombine m o p r) = some d := by
  simp [decodeVal_encodeVal, recombine_parts]

/-! ## The codec report -/

/-- What one format did with one domain. -/
structure FormatReport where
  /-- The format. -/
  fmt : Fmt
  /-- How long the file is. -/
  bytes : Nat
  /-- Whether it decoded at all. -/
  decoded : Bool
  /-- Whether what came back is the canonical graph. -/
  matchesCanonical : Bool
  /-- The canonical hash the file stands for. -/
  hash : List Char
deriving Repr

/-- The report of one format, computed rather than asserted. -/
def formatReport (f : Fmt) (d : Domain) : FormatReport :=
  { fmt := f
    bytes := (emit f d).length
    decoded := (parse f (emit f d)).isSome
    matchesCanonical := (parse f (emit f d)).map Domain.text == some d.text
    hash := d.hash }

/-- Every format the package emits. -/
def allFormats : List Fmt := [.ipdl, .xml, .csv, .yaml, .text]

/-- The round-trip report over all five formats. -/
def roundtripReport (d : Domain) : List FormatReport := allFormats.map (formatReport · d)

/-- **The round-trip report is honest**: it claims a match for a format
exactly when that format really returns the canonical graph, and it does
for every one of the five. -/
theorem roundtripReport_sound (d : Domain) :
    ∀ r ∈ roundtripReport d, r.decoded = true ∧ r.matchesCanonical = true ∧ r.hash = d.hash := by
  intro r hr
  simp only [roundtripReport, List.mem_map] at hr
  obtain ⟨f, _, rfl⟩ := hr
  refine ⟨?_, ?_, rfl⟩
  · simp [formatReport, parse_emit]
  · simp [formatReport, parse_emit]

/-- **Nothing is declared lossless that is not.**  The five formats of the
package are exactly the five that round-trip. -/
theorem no_undeclared_loss (d : Domain) :
    ∀ f ∈ allFormats, parse f (emit f d) = some d := fun f _ => parse_emit f d

end Kant.Dom
