/-
# The canonical proof object

The exchange standard's canonical model: a proof with its inputs, its
outputs, its intermediate artifacts, its errors, its provenance and its
status, plus the vocabularies (`Status`, `Severity`, `Fmt`, `Loss`) the
standard fixes.

Everything here is expressed *in* `Val` (`Kant.Codec.Val`), so a codec
only ever has to know how to move a `Val` into and out of its own syntax:

```text
Obj  ⇄  Val  ⇄  IPDL / XML / CSV / YAML / text
```

Proved here:

* `Obj.ofVal_toVal` — the canonical proof object survives the trip
  through `Val` **exactly**, every field, including the free-form
  `extensions` (`extensions_preserved`) — unknown data is not
  discardable;
* the same for every part: `Inp`, `Outp`, `Err`, `Trans`, `Prov`;
* `Obj.toVal_injective` — distinct objects have distinct canonical
  values, so `Obj.hash` is a content identity;
* `statusName_injective`, `status_ne_error_of_invalid` — the status
  vocabulary is a vocabulary: no status is silently another;
* `minimal_roundTrip` — the minimal interchange profile round-trips on
  its own fields, and `minimal_lossy` — it is genuinely a projection,
  so a system that implements only the minimum knows that it does.
-/
import Mathlib
import RequestProject.Kant.Codec.Val

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.Codec

/-! ## Vocabularies -/

/-- The standard status vocabulary. -/
inductive Status
  | unknown | pending | valid | invalid | partialResult | error | conflict | unsupported
deriving DecidableEq, Repr, Inhabited

/-- The severity of a diagnostic. -/
inductive Severity
  | info | warning | error | fatal
deriving DecidableEq, Repr, Inhabited

/-- The formats the codec speaks. -/
inductive Fmt
  | canonical | ipdl | xml | csv | yaml | text | unknown
deriving DecidableEq, Repr, Inhabited

/-- The preservation level a conversion must declare. -/
inductive Loss
  | lossless | lossy | partialLoss | failed
deriving DecidableEq, Repr, Inhabited

/-- The name of a status. -/
def Status.name : Status → List Char
  | .unknown => "UNKNOWN".toList
  | .pending => "PENDING".toList
  | .valid => "VALID".toList
  | .invalid => "INVALID".toList
  | .partialResult => "PARTIAL".toList
  | .error => "ERROR".toList
  | .conflict => "CONFLICT".toList
  | .unsupported => "UNSUPPORTED".toList

/-- Reading a status name. -/
def Status.ofName (s : List Char) : Option Status :=
  if s = "UNKNOWN".toList then some .unknown
  else if s = "PENDING".toList then some .pending
  else if s = "VALID".toList then some .valid
  else if s = "INVALID".toList then some .invalid
  else if s = "PARTIAL".toList then some .partialResult
  else if s = "ERROR".toList then some .error
  else if s = "CONFLICT".toList then some .conflict
  else if s = "UNSUPPORTED".toList then some .unsupported
  else none

@[simp] theorem Status.ofName_name (s : Status) : Status.ofName s.name = some s := by
  cases s <;> decide

/-- **No status is silently another.** -/
theorem statusName_injective {a b : Status} (h : a.name = b.name) : a = b := by
  have := Status.ofName_name a
  rw [h, Status.ofName_name b] at this
  exact (Option.some.inj this).symm

/-- `ERROR` (the system could not complete the operation) and `INVALID`
(the operation completed and the result failed validation) are different
outcomes. -/
theorem status_error_ne_invalid : Status.error ≠ Status.invalid := by decide

/-- The name of a severity. -/
def Severity.name : Severity → List Char
  | .info => "INFO".toList
  | .warning => "WARNING".toList
  | .error => "ERROR".toList
  | .fatal => "FATAL".toList

/-- Reading a severity name. -/
def Severity.ofName (s : List Char) : Option Severity :=
  if s = "INFO".toList then some .info
  else if s = "WARNING".toList then some .warning
  else if s = "ERROR".toList then some .error
  else if s = "FATAL".toList then some .fatal
  else none

@[simp] theorem Severity.ofName_name (s : Severity) : Severity.ofName s.name = some s := by
  cases s <;> decide

/-- The name of a format. -/
def Fmt.name : Fmt → List Char
  | .canonical => "canonical".toList
  | .ipdl => "ipdl".toList
  | .xml => "xml".toList
  | .csv => "csv".toList
  | .yaml => "yaml".toList
  | .text => "text".toList
  | .unknown => "unknown".toList

/-- Reading a format name. -/
def Fmt.ofName (s : List Char) : Option Fmt :=
  if s = "canonical".toList then some .canonical
  else if s = "ipdl".toList then some .ipdl
  else if s = "xml".toList then some .xml
  else if s = "csv".toList then some .csv
  else if s = "yaml".toList then some .yaml
  else if s = "text".toList then some .text
  else if s = "unknown".toList then some .unknown
  else none

@[simp] theorem Fmt.ofName_name (f : Fmt) : Fmt.ofName f.name = some f := by
  cases f <;> decide

/-- The name of a preservation level. -/
def Loss.name : Loss → List Char
  | .lossless => "LOSSLESS".toList
  | .lossy => "LOSSY".toList
  | .partialLoss => "PARTIAL".toList
  | .failed => "FAILED".toList

/-- Reading a preservation level. -/
def Loss.ofName (s : List Char) : Option Loss :=
  if s = "LOSSLESS".toList then some .lossless
  else if s = "LOSSY".toList then some .lossy
  else if s = "PARTIAL".toList then some .partialLoss
  else if s = "FAILED".toList then some .failed
  else none

@[simp] theorem Loss.ofName_name (l : Loss) : Loss.ofName l.name = some l := by
  cases l <;> decide

/-! ## Reading fields out of a canonical value -/

/-- The value stored under a key. -/
def lookupF (fs : List (List Char × Val)) (k : List Char) : Option Val :=
  match fs with
  | [] => none
  | (k', v) :: rest => if k' = k then some v else lookupF rest k

/-- A string field. -/
def getStr (fs : List (List Char × Val)) (k : List Char) : Option (List Char) :=
  match lookupF fs k with | some (.str s) => some s | _ => none

/-- An integer field. -/
def getInt (fs : List (List Char × Val)) (k : List Char) : Option Int :=
  match lookupF fs k with | some (.int n) => some n | _ => none

/-- A counting field. -/
def getNat (fs : List (List Char × Val)) (k : List Char) : Option Nat :=
  match lookupF fs k with | some (.int n) => if 0 ≤ n then some n.natAbs else none | _ => none

/-- A boolean field. -/
def getBool (fs : List (List Char × Val)) (k : List Char) : Option Bool :=
  match lookupF fs k with | some (.bool b) => some b | _ => none

/-- A field holding a value of any shape. -/
def getVal (fs : List (List Char × Val)) (k : List Char) : Option Val := lookupF fs k

/-- A list field. -/
def getList (fs : List (List Char × Val)) (k : List Char) : Option (List Val) :=
  match lookupF fs k with | some (.list xs) => some xs | _ => none

/-- A field holding free-form keyed data (`metadata`, `parameters`,
`extensions`). -/
def getObj (fs : List (List Char × Val)) (k : List Char) : Option (List (List Char × Val)) :=
  match lookupF fs k with | some (.obj kvs) => some kvs | _ => none

/-- An optional sub-object: `null` stands for "absent". -/
def optVal {α : Type} (f : α → Val) : Option α → Val
  | none => .null
  | some a => f a

/-- Reading an optional sub-object. -/
def optOf {α : Type} (g : Val → Option α) : Val → Option (Option α)
  | .null => some none
  | v => (g v).map some

/-- Decoding a list of sub-objects. -/
def listOf {α : Type} (g : Val → Option α) (xs : List Val) : Option (List α) := xs.mapM g

theorem listOf_map {α : Type} {f : α → Val} {g : Val → Option α}
    (h : ∀ a, g (f a) = some a) (xs : List α) : listOf g (xs.map f) = some xs := by
  induction xs with
  | nil => rfl
  | cons a as ih =>
      simp only [listOf, List.map_cons, List.mapM_cons, h a] at ih ⊢
      rw [ih]
      rfl

/-! ## Errors -/

/-- An error is a first-class exchange object. -/
structure Err where
  id : List Char
  code : List Char
  severity : Severity
  message : List Char
  location : List Char
  field : List Char
  objectId : List Char
  sourceSystem : List Char
  sourceFormat : Fmt
  expected : List Char
  actual : List Char
  cause : List Char
  resolution : List Char
  recoverable : Bool
deriving Repr, Inhabited

/-- An error as a canonical value. -/
def Err.toVal (e : Err) : Val :=
  .obj [("id".toList, .str e.id), ("code".toList, .str e.code),
        ("severity".toList, .str e.severity.name), ("message".toList, .str e.message),
        ("location".toList, .str e.location), ("field".toList, .str e.field),
        ("object_id".toList, .str e.objectId), ("source_system".toList, .str e.sourceSystem),
        ("source_format".toList, .str e.sourceFormat.name), ("expected".toList, .str e.expected),
        ("actual".toList, .str e.actual), ("cause".toList, .str e.cause),
        ("resolution".toList, .str e.resolution), ("recoverable".toList, .bool e.recoverable)]

/-- An error read back out of a canonical value. -/
def Err.ofVal : Val → Option Err
  | .obj fs => do
      let id ← getStr fs "id".toList
      let code ← getStr fs "code".toList
      let severity ← (getStr fs "severity".toList).bind Severity.ofName
      let message ← getStr fs "message".toList
      let location ← getStr fs "location".toList
      let field ← getStr fs "field".toList
      let objectId ← getStr fs "object_id".toList
      let sourceSystem ← getStr fs "source_system".toList
      let sourceFormat ← (getStr fs "source_format".toList).bind Fmt.ofName
      let expected ← getStr fs "expected".toList
      let actual ← getStr fs "actual".toList
      let cause ← getStr fs "cause".toList
      let resolution ← getStr fs "resolution".toList
      let recoverable ← getBool fs "recoverable".toList
      pure { id, code, severity, message, location, field, objectId, sourceSystem,
             sourceFormat, expected, actual, cause, resolution, recoverable }
  | _ => none

@[simp] theorem Err.ofVal_toVal (e : Err) : Err.ofVal e.toVal = some e := by
  cases e
  simp +decide [Err.ofVal, Err.toVal, getStr, getBool, lookupF]

/-! ## Transformations and provenance -/

/-- One conversion, recorded. -/
structure Trans where
  id : List Char
  operation : List Char
  source : Fmt
  dest : Fmt
  inputHash : List Char
  outputHash : List Char
  codec : Fmt
  codecVersion : List Char
  lossiness : Loss
  errors : List Err
  warnings : List Err
deriving Repr, Inhabited

/-- A transformation record as a canonical value. -/
def Trans.toVal (t : Trans) : Val :=
  .obj [("id".toList, .str t.id), ("operation".toList, .str t.operation),
        ("source".toList, .str t.source.name), ("destination".toList, .str t.dest.name),
        ("input_hash".toList, .str t.inputHash), ("output_hash".toList, .str t.outputHash),
        ("codec".toList, .str t.codec.name), ("codec_version".toList, .str t.codecVersion),
        ("lossiness".toList, .str t.lossiness.name),
        ("errors".toList, .list (t.errors.map Err.toVal)),
        ("warnings".toList, .list (t.warnings.map Err.toVal))]

/-- A transformation record read back. -/
def Trans.ofVal : Val → Option Trans
  | .obj fs => do
      let id ← getStr fs "id".toList
      let operation ← getStr fs "operation".toList
      let source ← (getStr fs "source".toList).bind Fmt.ofName
      let dest ← (getStr fs "destination".toList).bind Fmt.ofName
      let inputHash ← getStr fs "input_hash".toList
      let outputHash ← getStr fs "output_hash".toList
      let codec ← (getStr fs "codec".toList).bind Fmt.ofName
      let codecVersion ← getStr fs "codec_version".toList
      let lossiness ← (getStr fs "lossiness".toList).bind Loss.ofName
      let errors ← (getList fs "errors".toList).bind (listOf Err.ofVal)
      let warnings ← (getList fs "warnings".toList).bind (listOf Err.ofVal)
      pure { id, operation, source, dest, inputHash, outputHash, codec, codecVersion,
             lossiness, errors, warnings }
  | _ => none

@[simp] theorem Trans.ofVal_toVal (t : Trans) : Trans.ofVal t.toVal = some t := by
  cases t
  simp +decide [Trans.ofVal, Trans.toVal, getStr, getList, lookupF,
    listOf_map Err.ofVal_toVal]

/-- Where an object came from and what was done to it. -/
structure Prov where
  sourceSystem : List Char
  sourceFile : List Char
  sourceFormat : Fmt
  importedAt : Nat
  transformedAt : Nat
  transformations : List Trans
  parent : List Char
deriving Repr, Inhabited

/-- Provenance as a canonical value. -/
def Prov.toVal (p : Prov) : Val :=
  .obj [("source_system".toList, .str p.sourceSystem), ("source_file".toList, .str p.sourceFile),
        ("source_format".toList, .str p.sourceFormat.name),
        ("imported_at".toList, .int p.importedAt), ("transformed_at".toList, .int p.transformedAt),
        ("transformations".toList, .list (p.transformations.map Trans.toVal)),
        ("parent_object".toList, .str p.parent)]

/-- Provenance read back. -/
def Prov.ofVal : Val → Option Prov
  | .obj fs => do
      let sourceSystem ← getStr fs "source_system".toList
      let sourceFile ← getStr fs "source_file".toList
      let sourceFormat ← (getStr fs "source_format".toList).bind Fmt.ofName
      let importedAt ← getNat fs "imported_at".toList
      let transformedAt ← getNat fs "transformed_at".toList
      let transformations ← (getList fs "transformations".toList).bind (listOf Trans.ofVal)
      let parent ← getStr fs "parent_object".toList
      pure { sourceSystem, sourceFile, sourceFormat, importedAt, transformedAt,
             transformations, parent }
  | _ => none

@[simp] theorem Prov.ofVal_toVal (p : Prov) : Prov.ofVal p.toVal = some p := by
  cases p
  simp +decide [Prov.ofVal, Prov.toVal, getStr, getNat, getList, lookupF,
    listOf_map Trans.ofVal_toVal]

/-! ## Inputs and outputs -/

/-- An explicitly identified object consumed by a proof. -/
structure Inp where
  id : List Char
  name : List Char
  type : List Char
  value : Val
  encoding : List Char
  units : List Char
  constraints : List Val
  provenance : Option Prov
deriving Inhabited

/-- An input as a canonical value. -/
def Inp.toVal (i : Inp) : Val :=
  .obj [("id".toList, .str i.id), ("name".toList, .str i.name), ("type".toList, .str i.type),
        ("value".toList, i.value), ("encoding".toList, .str i.encoding),
        ("units".toList, .str i.units), ("constraints".toList, .list i.constraints),
        ("provenance".toList, optVal Prov.toVal i.provenance)]

/-- An input read back. -/
def Inp.ofVal : Val → Option Inp
  | .obj fs => do
      let id ← getStr fs "id".toList
      let name ← getStr fs "name".toList
      let type ← getStr fs "type".toList
      let value ← getVal fs "value".toList
      let encoding ← getStr fs "encoding".toList
      let units ← getStr fs "units".toList
      let constraints ← getList fs "constraints".toList
      let provenance ← (getVal fs "provenance".toList).bind (optOf Prov.ofVal)
      pure { id, name, type, value, encoding, units, constraints, provenance }
  | _ => none

/-- An object produced by a proof or a computation. -/
structure Outp where
  id : List Char
  name : List Char
  type : List Char
  value : Val
  encoding : List Char
  claims : List Val
  certificate : Val
  provenance : Option Prov
deriving Inhabited

/-- An output as a canonical value. -/
def Outp.toVal (o : Outp) : Val :=
  .obj [("id".toList, .str o.id), ("name".toList, .str o.name), ("type".toList, .str o.type),
        ("value".toList, o.value), ("encoding".toList, .str o.encoding),
        ("claims".toList, .list o.claims), ("certificate".toList, o.certificate),
        ("provenance".toList, optVal Prov.toVal o.provenance)]

/-- An output read back. -/
def Outp.ofVal : Val → Option Outp
  | .obj fs => do
      let id ← getStr fs "id".toList
      let name ← getStr fs "name".toList
      let type ← getStr fs "type".toList
      let value ← getVal fs "value".toList
      let encoding ← getStr fs "encoding".toList
      let claims ← getList fs "claims".toList
      let certificate ← getVal fs "certificate".toList
      let provenance ← (getVal fs "provenance".toList).bind (optOf Prov.ofVal)
      pure { id, name, type, value, encoding, claims, certificate, provenance }
  | _ => none

theorem optOf_optVal {α : Type} {f : α → Val} {g : Val → Option α}
    (hf : ∀ a, ∃ fs, f a = Val.obj fs) (h : ∀ a, g (f a) = some a) :
    ∀ p : Option α, optOf g (optVal f p) = some p
  | none => rfl
  | some a => by
      obtain ⟨fs, hfs⟩ := hf a
      have hred : optOf g (f a) = (g (f a)).map some := by rw [hfs]; rfl
      simp [optVal, hred, h a]

theorem optOf_Prov (p : Option Prov) : optOf Prov.ofVal (optVal Prov.toVal p) = some p :=
  optOf_optVal (fun _ => ⟨_, rfl⟩) Prov.ofVal_toVal p

@[simp] theorem Inp.ofVal_toVal (i : Inp) : Inp.ofVal i.toVal = some i := by
  cases i
  simp +decide [Inp.ofVal, Inp.toVal, getStr, getVal, getList, lookupF, optOf_Prov]

@[simp] theorem Outp.ofVal_toVal (o : Outp) : Outp.ofVal o.toVal = some o := by
  cases o
  simp +decide [Outp.ofVal, Outp.toVal, getStr, getVal, getList, lookupF, optOf_Prov]

/-! ## The proof object -/

/-- The canonical proof object.  `id`, `kind`, `inputs`, `outputs` and
`status` are the required fields; the rest may be empty when unavailable,
and `extensions` carries whatever the sending system knew and this one
does not. -/
structure Obj where
  id : List Char
  version : List Char
  kind : List Char
  inputs : List Inp
  assumptions : List Val
  parameters : List (List Char × Val)
  procedure : List Char
  intermediate : List Val
  outputs : List Outp
  claims : List Val
  certificates : List Val
  errors : List Err
  warnings : List Err
  provenance : Option Prov
  metadata : List (List Char × Val)
  sourceFormat : Fmt
  sourceData : List Char
  status : Status
  extensions : List (List Char × Val)
deriving Inhabited

/-- The proof object as a canonical value. -/
def Obj.toVal (o : Obj) : Val :=
  .obj [("id".toList, .str o.id), ("version".toList, .str o.version),
        ("kind".toList, .str o.kind), ("inputs".toList, .list (o.inputs.map Inp.toVal)),
        ("assumptions".toList, .list o.assumptions), ("parameters".toList, .obj o.parameters),
        ("procedure".toList, .str o.procedure), ("intermediate".toList, .list o.intermediate),
        ("outputs".toList, .list (o.outputs.map Outp.toVal)),
        ("claims".toList, .list o.claims), ("certificates".toList, .list o.certificates),
        ("errors".toList, .list (o.errors.map Err.toVal)),
        ("warnings".toList, .list (o.warnings.map Err.toVal)),
        ("provenance".toList, optVal Prov.toVal o.provenance),
        ("metadata".toList, .obj o.metadata),
        ("source_format".toList, .str o.sourceFormat.name),
        ("source_data".toList, .str o.sourceData),
        ("status".toList, .str o.status.name),
        ("extensions".toList, .obj o.extensions)]

/-- The proof object read back out of a canonical value. -/
def Obj.ofVal : Val → Option Obj
  | .obj fs => do
      let id ← getStr fs "id".toList
      let version ← getStr fs "version".toList
      let kind ← getStr fs "kind".toList
      let inputs ← (getList fs "inputs".toList).bind (listOf Inp.ofVal)
      let assumptions ← getList fs "assumptions".toList
      let parameters ← getObj fs "parameters".toList
      let procedure ← getStr fs "procedure".toList
      let intermediate ← getList fs "intermediate".toList
      let outputs ← (getList fs "outputs".toList).bind (listOf Outp.ofVal)
      let claims ← getList fs "claims".toList
      let certificates ← getList fs "certificates".toList
      let errors ← (getList fs "errors".toList).bind (listOf Err.ofVal)
      let warnings ← (getList fs "warnings".toList).bind (listOf Err.ofVal)
      let provenance ← (getVal fs "provenance".toList).bind (optOf Prov.ofVal)
      let metadata ← getObj fs "metadata".toList
      let sourceFormat ← (getStr fs "source_format".toList).bind Fmt.ofName
      let sourceData ← getStr fs "source_data".toList
      let status ← (getStr fs "status".toList).bind Status.ofName
      let extensions ← getObj fs "extensions".toList
      pure { id, version, kind, inputs, assumptions, parameters, procedure, intermediate,
             outputs, claims, certificates, errors, warnings, provenance, metadata,
             sourceFormat, sourceData, status, extensions }
  | _ => none

/-- **The canonical proof object survives the trip through `Val`.** -/
@[simp] theorem Obj.ofVal_toVal (o : Obj) : Obj.ofVal o.toVal = some o := by
  cases o
  simp +decide [Obj.ofVal, Obj.toVal, getStr, getVal, getList, getObj, lookupF, optOf_Prov,
    listOf_map Inp.ofVal_toVal, listOf_map Outp.ofVal_toVal, listOf_map Err.ofVal_toVal]

/-- **Unknown data is not discardable.** -/
theorem extensions_preserved (o : Obj) :
    (Obj.ofVal o.toVal).map Obj.extensions = some o.extensions := by
  simp

/-- Distinct proof objects have distinct canonical values. -/
theorem Obj.toVal_injective {a b : Obj} (h : a.toVal = b.toVal) : a = b := by
  have ha := Obj.ofVal_toVal a
  rw [h, Obj.ofVal_toVal b] at ha
  exact (Option.some.inj ha).symm

/-- The canonical text of a proof object. -/
def Obj.text (o : Obj) : List Char := canonEnc o.toVal

/-- The content identity of a proof object. -/
def Obj.hash (o : Obj) : List Char := valHash o.toVal

/-- **The canonical text determines the object**: content identity is
well defined. -/
theorem Obj.eq_of_text_eq {a b : Obj} (h : a.text = b.text) : a = b :=
  Obj.toVal_injective (canonEnc_injective h)

theorem Obj.hash_eq_of_eq {a b : Obj} (h : a = b) : a.hash = b.hash := by rw [h]

/-! ## The minimal interchange profile

A system that cannot implement the whole specification must still be able
to exchange `id`, `kind`, `inputs`, `outputs`, `status`, `errors` and
`metadata`. -/

/-- The minimal profile of a proof object. -/
def Obj.minimal (o : Obj) : Val :=
  .obj [("id".toList, .str o.id), ("kind".toList, .str o.kind),
        ("inputs".toList, .list (o.inputs.map Inp.toVal)),
        ("outputs".toList, .list (o.outputs.map Outp.toVal)),
        ("status".toList, .str o.status.name),
        ("errors".toList, .list (o.errors.map Err.toVal)),
        ("metadata".toList, .obj o.metadata)]

/-- What the minimal profile carries. -/
structure MinProfile where
  id : List Char
  kind : List Char
  inputs : List Inp
  outputs : List Outp
  status : Status
  errors : List Err
  metadata : List (List Char × Val)
deriving Inhabited

/-- Reading the minimal profile. -/
def minOfVal : Val → Option MinProfile
  | .obj fs => do
      let id ← getStr fs "id".toList
      let kind ← getStr fs "kind".toList
      let inputs ← (getList fs "inputs".toList).bind (listOf Inp.ofVal)
      let outputs ← (getList fs "outputs".toList).bind (listOf Outp.ofVal)
      let status ← (getStr fs "status".toList).bind Status.ofName
      let errors ← (getList fs "errors".toList).bind (listOf Err.ofVal)
      let metadata ← getObj fs "metadata".toList
      pure { id, kind, inputs, outputs, status, errors, metadata }
  | _ => none

/-- The minimal profile of a full object. -/
def Obj.minProfile (o : Obj) : MinProfile :=
  { id := o.id, kind := o.kind, inputs := o.inputs, outputs := o.outputs,
    status := o.status, errors := o.errors, metadata := o.metadata }

/-- **The minimal profile round-trips on its own fields**, so even a
simple tool can take part in the exchange. -/
theorem minimal_roundTrip (o : Obj) : minOfVal o.minimal = some o.minProfile := by
  cases o
  simp +decide [minOfVal, Obj.minimal, Obj.minProfile, getStr, getList, getObj, lookupF,
    listOf_map Inp.ofVal_toVal, listOf_map Outp.ofVal_toVal, listOf_map Err.ofVal_toVal]

/-- **And the minimal profile is a projection, not the object**: two
objects that differ outside the profile share it, which is why a codec
must not claim losslessness for the minimum. -/
theorem minimal_lossy :
    ∃ a b : Obj, a ≠ b ∧ a.minimal = b.minimal := by
  refine ⟨{ (default : Obj) with procedure := "replay".toList },
          { (default : Obj) with procedure := "recheck".toList }, ?_, ?_⟩
  · intro h
    have : "replay".toList = "recheck".toList := congrArg Obj.procedure h
    exact absurd this (by decide)
  · rfl

end Kant.Codec
