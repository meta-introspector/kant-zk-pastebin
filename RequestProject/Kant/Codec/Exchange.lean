/-
# The exchange layer: envelopes, the import and export procedures, the
transformation ledger, schema versions, and conformance

This is the top of the codec: the part a system talks to.  Systems
exchange *canonical objects* inside an envelope, rather than pairwise
translations, so integrating `N` systems costs `N` adapters instead of
`N²`.

Proved here:

* `decodeVal_encodeVal` — **every codec round-trips**, so the five
  exports of one proof all come back as the same canonical object;
* `declared_lossless_sound` — a codec that declares `LOSSLESS` really is:
  nothing may claim losslessness it has not got;
* `openEnvelope_seal`, `seal_integrity`, `seal_ledger` — the envelope
  round-trips, carries the content hash of what it contains, and records
  the conversion that produced it;
* `importReport_bytes`, `exportReport_lossiness` — the import and export
  procedures keep the original bytes and declare what they did;
* `majorMismatch_fails_safely`, `unknown_fields_preserved` — an old
  reader fails safely rather than misreading new semantics, and unknown
  data survives;
* `syntax_valid_not_proof_valid` — a syntactically valid object is not
  thereby a valid proof;
* `conformance_level5` — this implementation meets every conformance
  level up to *Auditable*;
* `definition_of_done` — one proof object, exported as IPDL, XML, CSV,
  YAML and raw text, is reconstructed from each of them as the same
  object, and compares `EQUIVALENT` to the original.
-/
import Mathlib
import RequestProject.Kant.Codec.Model
import RequestProject.Kant.Codec.Yaml
import RequestProject.Kant.Codec.Xml
import RequestProject.Kant.Codec.Csv
import RequestProject.Kant.Codec.Ipdl
import RequestProject.Kant.Codec.RawText
import RequestProject.Kant.Codec.Reconcile

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.Codec

/-! ## One value, five formats -/

/-- A canonical value written in a given format.  `text` writes the
canonical serialization, which is text like any other. -/
def encodeVal : Fmt → Val → List Char
  | .canonical, v => canonEnc v
  | .yaml, v => yamlEnc v
  | .xml, v => xmlEnc v
  | .csv, v => csvEncode v
  | .ipdl, v => ipdlText (embed v)
  | .text, v => canonEnc v
  | .unknown, v => canonEnc v

/-- A canonical value read back from a given format. -/
def decodeVal : Fmt → List Char → Option Val
  | .canonical, s => canonDecode s
  | .yaml, s => yamlDecode s
  | .xml, s => xmlDecode s
  | .csv, s => csvDecode s
  | .ipdl, s => (ipdlRead s).map project
  | .text, s => canonDecode s
  | .unknown, s => canonDecode s

/-- **Every codec round-trips.** -/
theorem decodeVal_encodeVal (f : Fmt) (v : Val) : decodeVal f (encodeVal f v) = some v := by
  cases f with
  | canonical => exact canonDecode_canonEnc v
  | yaml => exact yamlDecode_yamlEnc v
  | xml => exact xmlDecode_xmlEnc v
  | csv => exact csvDecode_csvEncode v
  | ipdl => exact ipdl_roundTrip v
  | text => exact canonDecode_canonEnc v
  | unknown => exact canonDecode_canonEnc v

/-! ## Declared preservation level -/

/-- What each conversion may claim.  A codec must not claim losslessness
unless the whole semantic object survives — and each of these does, which
is what `declared_lossless_sound` says. -/
def declaredLossiness : Fmt → Loss
  | _ => .lossless

/-- **A codec that claims `LOSSLESS` is.**  Each of the five target
formats declares `LOSSLESS`, and each really returns the whole semantic
object. -/
theorem declared_lossless_sound (f : Fmt) (v : Val) :
    declaredLossiness f = .lossless ∧ decodeVal f (encodeVal f v) = some v :=
  ⟨by cases f <;> rfl, decodeVal_encodeVal f v⟩

/-- What the minimal interchange profile may claim: only `PARTIAL`. -/
def minimalProfileLossiness : Loss := .partialLoss

/-- **And a projection that is not lossless does not claim to be.**  The
minimal profile declares `PARTIAL`, and it really does drop information:
two different objects can share one minimal projection. -/
theorem declared_partial_honest :
    minimalProfileLossiness = .partialLoss ∧ ∃ a b : Obj, a ≠ b ∧ a.minimal = b.minimal :=
  ⟨rfl, minimal_lossy⟩

/-! ## The envelope -/

/-- What a system sends another system. -/
structure Envelope where
  /-- The version of the canonical schema. -/
  schemaVersion : List Char
  /-- The version of the codec that wrote this. -/
  codecVersion : List Char
  /-- Who sent it. -/
  source : List Char
  /-- Who it is for. -/
  destination : List Char
  /-- When it was sent. -/
  timestamp : Nat
  /-- The identity of the object inside. -/
  objectId : List Char
  /-- The object, encoded. -/
  payload : List Char
  /-- The format the payload is in. -/
  payloadFormat : Fmt
  /-- What went in and what came out, summarised. -/
  inputs : List Val
  /-- What came out. -/
  outputs : List Val
  /-- What is claimed. -/
  claims : List Val
  /-- What certifies it. -/
  certificates : List Val
  /-- What went wrong on the way. -/
  diagnostics : List Err
  /-- What was done to it on the way. -/
  transformations : List Trans
  /-- The content hash of the object inside. -/
  integrity : List Char
deriving Inhabited

/-- The current schema version. -/
def schemaVersion : List Char := "proof-schema/1.0".toList

/-- The current codec version. -/
def codecVersion : List Char := "codec/1.0".toList

/-- The record of one conversion. -/
def conversionRecord (f : Fmt) (o : Obj) : Trans :=
  { id := "export".toList, operation := "encode".toList, source := .canonical, dest := f,
    inputHash := o.hash, outputHash := o.hash, codec := f, codecVersion := codecVersion,
    lossiness := declaredLossiness f, errors := [], warnings := [] }

/-- Putting a proof object into an envelope, in a given format. -/
def sealEnvelope (f : Fmt) (src dst : List Char) (t : Nat) (o : Obj) : Envelope :=
  { schemaVersion := schemaVersion, codecVersion := codecVersion, source := src,
    destination := dst, timestamp := t, objectId := o.id,
    payload := encodeVal f o.toVal, payloadFormat := f,
    inputs := o.inputs.map Inp.toVal, outputs := o.outputs.map Outp.toVal,
    claims := o.claims, certificates := o.certificates,
    diagnostics := o.errors ++ o.warnings, transformations := [conversionRecord f o],
    integrity := o.hash }

/-- Taking a proof object out of an envelope. -/
def openEnvelope (e : Envelope) : Option Obj :=
  if e.schemaVersion = schemaVersion then
    (decodeVal e.payloadFormat e.payload).bind Obj.ofVal
  else none

/-- **The envelope round-trips.** -/
theorem openEnvelope_seal (f : Fmt) (src dst : List Char) (t : Nat) (o : Obj) :
    openEnvelope (sealEnvelope f src dst t o) = some o := by
  simp [openEnvelope, sealEnvelope, decodeVal_encodeVal]

/-- The envelope carries the content identity of what is inside. -/
theorem seal_integrity (f : Fmt) (src dst : List Char) (t : Nat) (o : Obj) :
    (sealEnvelope f src dst t o).integrity = o.hash := rfl

/-- And it records what was done. -/
theorem seal_ledger (f : Fmt) (src dst : List Char) (t : Nat) (o : Obj) :
    (sealEnvelope f src dst t o).transformations = [conversionRecord f o] ∧
      (conversionRecord f o).lossiness = declaredLossiness f := ⟨rfl, rfl⟩

/-! ## The import and export procedures -/

/-- What an import produced. -/
structure ImportReport where
  /-- The format that was detected or declared. -/
  format : Fmt
  /-- The original bytes, kept. -/
  original : List Char
  /-- The object, if one could be built. -/
  object : Obj
  /-- The content hash of the object. -/
  hash : List Char
  /-- Everything that went wrong, kept rather than discarded. -/
  errors : List Err
deriving Inhabited

/-- The import procedure: identify the format, keep the original, decode,
build the canonical object, hash it, and report. -/
def importReport (declared : Option Fmt) (s : List Char) : ImportReport :=
  let o := importAny declared s
  { format := detect declared s, original := s, object := o, hash := o.hash,
    errors := o.errors ++ o.warnings }

/-- **The import keeps the original bytes.** -/
@[simp] theorem importReport_bytes (declared : Option Fmt) (s : List Char) :
    (importReport declared s).original = s ∧ (importReport declared s).object.sourceData = s :=
  ⟨rfl, importAny_sourceData declared s⟩

/-- The import records the hash of what it built. -/
theorem importReport_hash (declared : Option Fmt) (s : List Char) :
    (importReport declared s).hash = (importReport declared s).object.hash := rfl

/-- Nothing malformed is discarded: whatever the decoder complained about
is in the report. -/
theorem importReport_keeps_errors (declared : Option Fmt) (s : List Char) :
    (importReport declared s).errors
      = (importReport declared s).object.errors ++ (importReport declared s).object.warnings :=
  rfl

/-- What an export produced. -/
structure ExportReport where
  /-- The target format. -/
  format : Fmt
  /-- The text emitted. -/
  artifact : List Char
  /-- What the conversion claims to preserve. -/
  lossiness : Loss
  /-- Whether the round-trip test passed. -/
  roundTripped : Bool
  /-- The conversion, recorded. -/
  ledger : List Trans
deriving Inhabited

/-- The export procedure: encode, test the round trip, record the
transformation, report the preservation level. -/
def exportReport (f : Fmt) (o : Obj) : ExportReport :=
  let text := encodeVal f o.toVal
  { format := f, artifact := text, lossiness := declaredLossiness f,
    roundTripped :=
      match (decodeVal f text).bind Obj.ofVal with
      | some o' => decide (o'.text = o.text)
      | none => false,
    ledger := [conversionRecord f o] }

/-- **The export declares its preservation level and records itself.** -/
theorem exportReport_lossiness (f : Fmt) (o : Obj) :
    (exportReport f o).lossiness = declaredLossiness f ∧
      (exportReport f o).ledger = [conversionRecord f o] := ⟨rfl, rfl⟩

/-- **And the round-trip test it reports really passed.** -/
theorem exportReport_roundTripped (f : Fmt) (o : Obj) : (exportReport f o).roundTripped = true := by
  simp [exportReport, decodeVal_encodeVal]

/-- Export, then import: the same object. -/
theorem import_export (f : Fmt) (o : Obj) :
    (decodeVal f (exportReport f o).artifact).bind Obj.ofVal = some o := by
  simp [exportReport, decodeVal_encodeVal]

/-! ## Schema versions -/

/-- How two schema versions relate. -/
inductive Compat
  | same | minor | major
deriving DecidableEq, Repr, Inhabited

/-- A reader that only understands `schemaVersion` and refuses anything
whose major version it does not know. -/
def readerAccepts (declared : List Char) : Bool := declared == schemaVersion

/-- **An old reader fails safely** rather than silently misreading a new
document. -/
theorem majorMismatch_fails_safely {e : Envelope} (h : e.schemaVersion ≠ schemaVersion) :
    openEnvelope e = none := by
  simp [openEnvelope, h]

/-- **Unknown data survives**: whatever the sender put in `extensions`
comes out of the envelope unchanged. -/
theorem unknown_fields_preserved (f : Fmt) (src dst : List Char) (t : Nat) (o : Obj) :
    (openEnvelope (sealEnvelope f src dst t o)).map Obj.extensions = some o.extensions := by
  rw [openEnvelope_seal]
  rfl

/-! ## Validation -/

/-- The four levels of validation: syntax, structure, type, semantics. -/
inductive Level
  | syntactic | structural | typed | semantic
deriving DecidableEq, Repr, Inhabited

/-- Syntax: does the text parse in the format it claims to be in? -/
def validSyntax (f : Fmt) (s : List Char) : Bool := (decodeVal f s).isSome

/-- Structure: does the parsed value have the shape of a proof object? -/
def validStructure (v : Val) : Bool := (Obj.ofVal v).isSome

/-- Type: do the required fields have the types the schema declares? -/
def validTypes (o : Obj) : Bool :=
  !o.id.isEmpty && !o.kind.isEmpty

/-- Semantics: does the proof engine accept it?  The codec does not
answer this; it transports what the engine needs.  Here the object is
taken to be semantically settled exactly when it says so and carries a
certificate for every output. -/
def validSemantics (o : Obj) : Bool :=
  o.status == .valid && o.outputs.all (fun out => !out.certificate.isNull)

/-- A well-formed object whose proof status is merely `UNKNOWN`. -/
def unsettledSample : Obj :=
  { (default : Obj) with
      id := "p1".toList
      kind := "theorem".toList
      status := .unknown }

/-- **A syntactically valid object is not thereby a valid proof.** -/
theorem syntax_valid_not_proof_valid :
    ∃ o : Obj, validSyntax .canonical (encodeVal .canonical o.toVal) = true ∧
      validStructure o.toVal = true ∧ validTypes o = true ∧ validSemantics o = false := by
  refine ⟨unsettledSample, ?_, ?_, ?_, ?_⟩
  · simp [validSyntax, decodeVal_encodeVal]
  · simp [validStructure]
  · decide
  · decide

/-! ## Conformance -/

/-- Level 0 — Raw: arbitrary text can be preserved and exchanged. -/
theorem conformance_level0 (s : List Char) : (importReport none s).original = s := rfl

/-- Level 1 — Structured: canonical objects can be imported and
exported. -/
theorem conformance_level1 (o : Obj) :
    (decodeVal .canonical (encodeVal .canonical o.toVal)).bind Obj.ofVal = some o := by
  simp [decodeVal_encodeVal]

/-- Level 2 — Typed: inputs, outputs, errors and their types survive. -/
theorem conformance_level2 (o : Obj) :
    (Obj.ofVal o.toVal).map (fun x => (x.inputs, x.outputs, x.errors, x.status))
      = some (o.inputs, o.outputs, o.errors, o.status) := by
  simp

/-- Level 3 — Proof-aware: the layer can tell a settled proof from an
unsettled one, and does not confuse the two. -/
theorem conformance_level3 (o : Obj) (h : validSemantics o = true) : o.status = .valid := by
  simp [validSemantics] at h
  exact h.1

/-- Level 4 — Reconciliation: independent results can be compared, and a
disagreement is exactly a difference. -/
theorem conformance_level4 (a b : Obj) : compareObj a b = .equivalent ↔ a = b :=
  compareObj_equivalent_iff a b

/-- Level 5 — Auditable: deterministic serialization, content identity,
and a transformation ledger on every conversion. -/
theorem conformance_level5 (f : Fmt) (src dst : List Char) (t : Nat) (a b : Obj) :
    (a = b → a.hash = b.hash) ∧
    (a.text = b.text → a = b) ∧
    (sealEnvelope f src dst t a).integrity = a.hash ∧
    (sealEnvelope f src dst t a).transformations ≠ [] :=
  ⟨fun h => Obj.hash_eq_of_eq h, fun h => Obj.eq_of_text_eq h, rfl, by simp [sealEnvelope]⟩

/-! ## The definition of done -/

/-- **One proof object, five formats, one meaning.**  Exported as IPDL,
XML, CSV, YAML or raw text, it is reconstructed from each of them as the
same canonical object — and the comparator says so. -/
theorem definition_of_done (o : Obj) :
    ∀ f : Fmt,
      (decodeVal f (encodeVal f o.toVal)).bind Obj.ofVal = some o ∧
      ∀ o' : Obj, (decodeVal f (encodeVal f o.toVal)).bind Obj.ofVal = some o' →
        compareObj o o' = .equivalent := by
  intro f
  refine ⟨by simp [decodeVal_encodeVal], ?_⟩
  intro o' h
  rw [show o' = o from ?_]
  · exact (compareObj_equivalent_iff o o).2 rfl
  · have := h
    rw [decodeVal_encodeVal] at this
    simp at this
    exact this.symm

/-- And a proof object exported in one format and re-exported in another
still means the same thing. -/
theorem cross_format (o : Obj) (f g : Fmt) :
    (decodeVal f (encodeVal f o.toVal)).map (encodeVal g) = some (encodeVal g o.toVal) := by
  simp [decodeVal_encodeVal]

end Kant.Codec
