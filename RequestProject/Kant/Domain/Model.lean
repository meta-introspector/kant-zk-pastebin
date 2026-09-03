/-
# The canonical domain graph

The codec layer (`Kant.Codec`) moves *one proof object* between formats.
This layer is the thing the formats are projections *of*: a whole domain —
its data objects, the claims made about them, the proofs that establish
them, the relations between all of those, and the provenance of each.

```text
Domain
├── objects[]      the data of the domain
├── relations[]    the edges of the graph
├── proofs[]       the proof catalog
├── claims[]       what is asserted
├── evidence[]     what supports it
├── schemas[]      how it is shaped
├── errors[]       what went wrong
└── provenance[]   where it came from
```

Every domain object carries a *truth status* — `PROVEN` is not the same
statement as `ASSERTED` — and points at identifiable proof records rather
than at the string `"proved"`.  Every proof record says what it consumes,
what it produces, what it establishes, what it depends on, whether it is
`VALID`, and whether a machine has checked it.

Everything here encodes into `Kant.Codec.Val`, so the five codecs already
proved to round-trip carry a whole domain and not just one object.
-/
import Mathlib
import RequestProject.Kant.Codec.Model

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.Dom

open Kant.Codec

/-- An identifier: objects, proofs, claims and evidence are all named by
one of these, and every reference is a reference to one. -/
abbrev Id := List Char

/-! ## Vocabularies -/

/-- The provenance of truth of a domain value.  These are *not*
interchangeable: `PROVEN` names a value established by a proof record,
`ASSERTED` a value someone simply wrote down. -/
inductive Truth
  | proven | derived | verified | asserted | imported | inferred
  | unresolved | contradicted | invalid
deriving Repr, Inhabited, DecidableEq

/-- What a proof record reports about itself. -/
inductive PStatus
  | valid | invalid | «partial» | failed | unknown | conflict
deriving Repr, Inhabited, DecidableEq

/-- How much evidence stands behind a proof: it exists, a machine checked
it, or an independent system reproduced it.  These are three states, not
one. -/
inductive Evid
  | none | stated | machineChecked | reproduced
deriving Repr, Inhabited, DecidableEq

/-- The edges of the domain graph. -/
inductive Rel
  | inputTo | outputOf | proves | provenBy | derives | verifies | constrains
  | dependsOn | references | contradicts | reproduces | encodes | decodes
deriving Repr, Inhabited, DecidableEq

/-- Proof coverage of a single domain object. -/
inductive Coverage
  | proven | partiallyProven | unproven | contradicted
deriving Repr, Inhabited, DecidableEq

/-- The wire name of a truth status. -/
def Truth.name : Truth → List Char
  | .proven => "PROVEN".toList
  | .derived => "DERIVED".toList
  | .verified => "VERIFIED".toList
  | .asserted => "ASSERTED".toList
  | .imported => "IMPORTED".toList
  | .inferred => "INFERRED".toList
  | .unresolved => "UNRESOLVED".toList
  | .contradicted => "CONTRADICTED".toList
  | .invalid => "INVALID".toList

/-- A truth status read back from its wire name. -/
def Truth.ofName (s : List Char) : Option Truth :=
  if s = "PROVEN".toList then some .proven
  else if s = "DERIVED".toList then some .derived
  else if s = "VERIFIED".toList then some .verified
  else if s = "ASSERTED".toList then some .asserted
  else if s = "IMPORTED".toList then some .imported
  else if s = "INFERRED".toList then some .inferred
  else if s = "UNRESOLVED".toList then some .unresolved
  else if s = "CONTRADICTED".toList then some .contradicted
  else if s = "INVALID".toList then some .invalid
  else none

@[simp] theorem Truth.ofName_name (t : Truth) : Truth.ofName t.name = some t := by
  cases t <;> decide

/-- **The truth statuses are distinguishable.**  `ASSERTED` cannot quietly
travel as `PROVEN`, because their names differ. -/
theorem truthName_injective {a b : Truth} (h : a.name = b.name) : a = b := by
  have := congrArg Truth.ofName h
  simpa using this

/-- The wire name of a proof status. -/
def PStatus.name : PStatus → List Char
  | .valid => "VALID".toList
  | .invalid => "INVALID".toList
  | .«partial» => "PARTIAL".toList
  | .failed => "FAILED".toList
  | .unknown => "UNKNOWN".toList
  | .conflict => "CONFLICT".toList

/-- A proof status read back. -/
def PStatus.ofName (s : List Char) : Option PStatus :=
  if s = "VALID".toList then some .valid
  else if s = "INVALID".toList then some .invalid
  else if s = "PARTIAL".toList then some .«partial»
  else if s = "FAILED".toList then some .failed
  else if s = "UNKNOWN".toList then some .unknown
  else if s = "CONFLICT".toList then some .conflict
  else none

@[simp] theorem PStatus.ofName_name (s : PStatus) : PStatus.ofName s.name = some s := by
  cases s <;> decide

/-- **Proof statuses are distinguishable too.** -/
theorem pstatusName_injective {a b : PStatus} (h : a.name = b.name) : a = b := by
  have := congrArg PStatus.ofName h
  simpa using this

/-- The wire name of an evidence level. -/
def Evid.name : Evid → List Char
  | .none => "NONE".toList
  | .stated => "STATED".toList
  | .machineChecked => "MACHINE_CHECKED".toList
  | .reproduced => "REPRODUCED".toList

/-- An evidence level read back. -/
def Evid.ofName (s : List Char) : Option Evid :=
  if s = "NONE".toList then some .none
  else if s = "STATED".toList then some .stated
  else if s = "MACHINE_CHECKED".toList then some .machineChecked
  else if s = "REPRODUCED".toList then some .reproduced
  else none

@[simp] theorem Evid.ofName_name (e : Evid) : Evid.ofName e.name = some e := by
  cases e <;> decide

/-- **A proof that exists, a proof a machine checked, and a proof somebody
reproduced are three different states.** -/
theorem evidence_levels_distinct :
    Evid.stated ≠ Evid.machineChecked ∧ Evid.machineChecked ≠ Evid.reproduced ∧
      Evid.stated ≠ Evid.reproduced := by decide

/-- The wire name of a relation. -/
def Rel.name : Rel → List Char
  | .inputTo => "INPUT_TO".toList
  | .outputOf => "OUTPUT_OF".toList
  | .proves => "PROVES".toList
  | .provenBy => "PROVEN_BY".toList
  | .derives => "DERIVES".toList
  | .verifies => "VERIFIES".toList
  | .constrains => "CONSTRAINS".toList
  | .dependsOn => "DEPENDS_ON".toList
  | .references => "REFERENCES".toList
  | .contradicts => "CONTRADICTS".toList
  | .reproduces => "REPRODUCES".toList
  | .encodes => "ENCODES".toList
  | .decodes => "DECODES".toList

/-- A relation read back. -/
def Rel.ofName (s : List Char) : Option Rel :=
  if s = "INPUT_TO".toList then some .inputTo
  else if s = "OUTPUT_OF".toList then some .outputOf
  else if s = "PROVES".toList then some .proves
  else if s = "PROVEN_BY".toList then some .provenBy
  else if s = "DERIVES".toList then some .derives
  else if s = "VERIFIES".toList then some .verifies
  else if s = "CONSTRAINS".toList then some .constrains
  else if s = "DEPENDS_ON".toList then some .dependsOn
  else if s = "REFERENCES".toList then some .references
  else if s = "CONTRADICTS".toList then some .contradicts
  else if s = "REPRODUCES".toList then some .reproduces
  else if s = "ENCODES".toList then some .encodes
  else if s = "DECODES".toList then some .decodes
  else none

@[simp] theorem Rel.ofName_name (r : Rel) : Rel.ofName r.name = some r := by
  cases r <;> decide

/-- The wire name of a coverage class. -/
def Coverage.name : Coverage → List Char
  | .proven => "PROVEN".toList
  | .partiallyProven => "PARTIALLY_PROVEN".toList
  | .unproven => "UNPROVEN".toList
  | .contradicted => "CONTRADICTED".toList

/-- A coverage class read back. -/
def Coverage.ofName (s : List Char) : Option Coverage :=
  if s = "PROVEN".toList then some .proven
  else if s = "PARTIALLY_PROVEN".toList then some .partiallyProven
  else if s = "UNPROVEN".toList then some .unproven
  else if s = "CONTRADICTED".toList then some .contradicted
  else none

@[simp] theorem Coverage.ofName_name (c : Coverage) : Coverage.ofName c.name = some c := by
  cases c <;> decide

/-! ## Lists of identifiers -/

/-- A list of identifiers as a canonical value. -/
def idsVal (xs : List Id) : Val := .list (xs.map Val.str)

/-- One identifier read back. -/
def idOfVal : Val → Option Id
  | .str s => some s
  | _ => none

@[simp] theorem idOfVal_str (s : Id) : idOfVal (.str s) = some s := rfl

/-- A list of identifiers stored under a key. -/
def getIds (fs : List (List Char × Val)) (k : List Char) : Option (List Id) :=
  (getList fs k).bind (listOf idOfVal)

@[simp] theorem listOf_idsVal (xs : List Id) : listOf idOfVal (xs.map Val.str) = some xs :=
  listOf_map (f := Val.str) idOfVal_str xs

/-! ## Certificates -/

/-- A machine-checkable certificate attached to a proof. -/
structure Cert where
  /-- What kind of certificate this is (`lean-kernel`, `sha256`, …). -/
  kind : List Char
  /-- Its digest. -/
  digest : List Char
  /-- Where it can be found. -/
  location : List Char
  /-- How much evidence it represents. -/
  evidence : Evid
deriving Repr, Inhabited, DecidableEq

/-- A certificate as a canonical value. -/
def Cert.toVal (c : Cert) : Val :=
  .obj [("kind".toList, .str c.kind), ("digest".toList, .str c.digest),
        ("location".toList, .str c.location), ("evidence".toList, .str c.evidence.name)]

/-- A certificate read back. -/
def Cert.ofVal : Val → Option Cert
  | .obj fs => do
      let kind ← getStr fs "kind".toList
      let digest ← getStr fs "digest".toList
      let location ← getStr fs "location".toList
      let evidence ← (getStr fs "evidence".toList).bind Evid.ofName
      pure { kind, digest, location, evidence }
  | _ => none

@[simp] theorem Cert.ofVal_toVal (c : Cert) : Cert.ofVal c.toVal = some c := by
  cases c
  simp +decide [Cert.ofVal, Cert.toVal, getStr, lookupF]

@[simp] theorem optOf_Cert (c : Option Cert) : optOf Cert.ofVal (optVal Cert.toVal c) = some c :=
  optOf_optVal (fun _ => ⟨_, rfl⟩) Cert.ofVal_toVal c

@[simp] theorem optOf_Prov' (p : Option Prov) : optOf Prov.ofVal (optVal Prov.toVal p) = some p :=
  optOf_Prov p

/-! ## Domain objects -/

/-- A datum of the domain: the canonical unit everything else hangs off.
It names its inputs, its parameters, the transformations that produced it,
its outputs, the claims made about it, the evidence for it, the proofs
that establish it, the errors attached to it, and where it came from. -/
structure DomObj where
  /-- The identifier of this object. -/
  id : Id
  /-- What kind of object it is (`theorem`, `datum`, `input`, …). -/
  kind : List Char
  /-- A human name. -/
  name : List Char
  /-- The value it holds, if it holds one. -/
  value : Val
  /-- What it claims, in words. -/
  claim : List Char
  /-- Objects consumed. -/
  inputs : List Id
  /-- Named parameters. -/
  parameters : List (List Char × Val)
  /-- Transformations applied. -/
  transformations : List Id
  /-- Objects produced. -/
  outputs : List Id
  /-- Claim records about this object. -/
  claimRefs : List Id
  /-- Evidence records. -/
  evidenceRefs : List Id
  /-- **The proofs that establish it** — identifiers, not adjectives. -/
  proofRefs : List Id
  /-- Errors attached to it. -/
  errorRefs : List Id
  /-- The provenance of its truth. -/
  truth : Truth
  /-- Where it came from. -/
  provenance : Option Prov
deriving Inhabited

/-- A domain object as a canonical value. -/
def DomObj.toVal (o : DomObj) : Val :=
  .obj [("id".toList, .str o.id), ("kind".toList, .str o.kind), ("name".toList, .str o.name),
        ("value".toList, o.value), ("claim".toList, .str o.claim),
        ("inputs".toList, idsVal o.inputs), ("parameters".toList, .obj o.parameters),
        ("transformations".toList, idsVal o.transformations),
        ("outputs".toList, idsVal o.outputs), ("claim_refs".toList, idsVal o.claimRefs),
        ("evidence_refs".toList, idsVal o.evidenceRefs),
        ("proof_refs".toList, idsVal o.proofRefs), ("error_refs".toList, idsVal o.errorRefs),
        ("truth".toList, .str o.truth.name),
        ("provenance".toList, optVal Prov.toVal o.provenance)]

/-- A domain object read back. -/
def DomObj.ofVal : Val → Option DomObj
  | .obj fs => do
      let id ← getStr fs "id".toList
      let kind ← getStr fs "kind".toList
      let name ← getStr fs "name".toList
      let value ← getVal fs "value".toList
      let claim ← getStr fs "claim".toList
      let inputs ← getIds fs "inputs".toList
      let parameters ← getObj fs "parameters".toList
      let transformations ← getIds fs "transformations".toList
      let outputs ← getIds fs "outputs".toList
      let claimRefs ← getIds fs "claim_refs".toList
      let evidenceRefs ← getIds fs "evidence_refs".toList
      let proofRefs ← getIds fs "proof_refs".toList
      let errorRefs ← getIds fs "error_refs".toList
      let truth ← (getStr fs "truth".toList).bind Truth.ofName
      let provenance ← (getVal fs "provenance".toList).bind (optOf Prov.ofVal)
      pure { id, kind, name, value, claim, inputs, parameters, transformations, outputs,
             claimRefs, evidenceRefs, proofRefs, errorRefs, truth, provenance }
  | _ => none

@[simp] theorem DomObj.ofVal_toVal (o : DomObj) : DomObj.ofVal o.toVal = some o := by
  cases o
  simp +decide [DomObj.ofVal, DomObj.toVal, getStr, getVal, getObj, getIds, getList,
    lookupF, idsVal]

/-! ## Proof records -/

/-- A catalog entry for one proof: what it consumes, what it produces,
what it establishes, what it depends on, whether it holds, and what
certificate stands behind it. -/
structure ProofRec where
  /-- The identifier of this proof. -/
  id : Id
  /-- Its name in the source system. -/
  name : List Char
  /-- What kind of proof it is (`lean`, `arithmetic`, `replication`, …). -/
  kind : List Char
  /-- The file it lives in. -/
  sourceFile : List Char
  /-- Where in that file. -/
  sourceLoc : List Char
  /-- The objects it consumes. -/
  inputRefs : List Id
  /-- What it assumes. -/
  assumptions : List Id
  /-- How it proceeds, in words. -/
  procedure : List Char
  /-- The objects it produces. -/
  outputRefs : List Id
  /-- The claims it establishes. -/
  claimRefs : List Id
  /-- The proofs it depends on. -/
  dependsOn : List Id
  /-- Whether it holds. -/
  status : PStatus
  /-- Its certificate, when it has one. -/
  certificate : Option Cert
  /-- The system it came from. -/
  source : List Char
  /-- Its provenance. -/
  provenance : Option Prov
deriving Inhabited

/-- A proof record as a canonical value. -/
def ProofRec.toVal (p : ProofRec) : Val :=
  .obj [("id".toList, .str p.id), ("name".toList, .str p.name), ("kind".toList, .str p.kind),
        ("source_file".toList, .str p.sourceFile), ("source_location".toList, .str p.sourceLoc),
        ("input_refs".toList, idsVal p.inputRefs), ("assumptions".toList, idsVal p.assumptions),
        ("procedure".toList, .str p.procedure), ("output_refs".toList, idsVal p.outputRefs),
        ("claim_refs".toList, idsVal p.claimRefs), ("dependencies".toList, idsVal p.dependsOn),
        ("status".toList, .str p.status.name),
        ("certificate".toList, optVal Cert.toVal p.certificate),
        ("source".toList, .str p.source),
        ("provenance".toList, optVal Prov.toVal p.provenance)]

/-- A proof record read back. -/
def ProofRec.ofVal : Val → Option ProofRec
  | .obj fs => do
      let id ← getStr fs "id".toList
      let name ← getStr fs "name".toList
      let kind ← getStr fs "kind".toList
      let sourceFile ← getStr fs "source_file".toList
      let sourceLoc ← getStr fs "source_location".toList
      let inputRefs ← getIds fs "input_refs".toList
      let assumptions ← getIds fs "assumptions".toList
      let procedure ← getStr fs "procedure".toList
      let outputRefs ← getIds fs "output_refs".toList
      let claimRefs ← getIds fs "claim_refs".toList
      let dependsOn ← getIds fs "dependencies".toList
      let status ← (getStr fs "status".toList).bind PStatus.ofName
      let certificate ← (getVal fs "certificate".toList).bind (optOf Cert.ofVal)
      let source ← getStr fs "source".toList
      let provenance ← (getVal fs "provenance".toList).bind (optOf Prov.ofVal)
      pure { id, name, kind, sourceFile, sourceLoc, inputRefs, assumptions, procedure,
             outputRefs, claimRefs, dependsOn, status, certificate, source, provenance }
  | _ => none

@[simp] theorem ProofRec.ofVal_toVal (p : ProofRec) : ProofRec.ofVal p.toVal = some p := by
  cases p
  simp +decide [ProofRec.ofVal, ProofRec.toVal, getStr, getVal, getIds, getList,
    lookupF, idsVal]

/-! ## Claims, evidence, relations, schemas -/

/-- Something asserted about a domain object. -/
structure Claim where
  /-- The identifier of this claim. -/
  id : Id
  /-- The object it is about. -/
  objectRef : Id
  /-- What it says. -/
  text : List Char
  /-- Its truth status. -/
  truth : Truth
  /-- The proofs that establish it. -/
  proofRefs : List Id
deriving Inhabited, DecidableEq

/-- A claim as a canonical value. -/
def Claim.toVal (c : Claim) : Val :=
  .obj [("id".toList, .str c.id), ("object_ref".toList, .str c.objectRef),
        ("text".toList, .str c.text), ("truth".toList, .str c.truth.name),
        ("proof_refs".toList, idsVal c.proofRefs)]

/-- A claim read back. -/
def Claim.ofVal : Val → Option Claim
  | .obj fs => do
      let id ← getStr fs "id".toList
      let objectRef ← getStr fs "object_ref".toList
      let text ← getStr fs "text".toList
      let truth ← (getStr fs "truth".toList).bind Truth.ofName
      let proofRefs ← getIds fs "proof_refs".toList
      pure { id, objectRef, text, truth, proofRefs }
  | _ => none

@[simp] theorem Claim.ofVal_toVal (c : Claim) : Claim.ofVal c.toVal = some c := by
  cases c
  simp +decide [Claim.ofVal, Claim.toVal, getStr, getIds, getList, lookupF, idsVal]

/-- Something that supports a claim without being a proof of it. -/
structure Evidence where
  /-- The identifier of this evidence record. -/
  id : Id
  /-- What kind of evidence (`test-run`, `measurement`, `citation`, …). -/
  kind : List Char
  /-- The object it supports. -/
  objectRef : Id
  /-- What it is. -/
  description : List Char
  /-- Where it can be found. -/
  location : List Char
deriving Inhabited, DecidableEq

/-- Evidence as a canonical value. -/
def Evidence.toVal (e : Evidence) : Val :=
  .obj [("id".toList, .str e.id), ("kind".toList, .str e.kind),
        ("object_ref".toList, .str e.objectRef), ("description".toList, .str e.description),
        ("location".toList, .str e.location)]

/-- Evidence read back. -/
def Evidence.ofVal : Val → Option Evidence
  | .obj fs => do
      let id ← getStr fs "id".toList
      let kind ← getStr fs "kind".toList
      let objectRef ← getStr fs "object_ref".toList
      let description ← getStr fs "description".toList
      let location ← getStr fs "location".toList
      pure { id, kind, objectRef, description, location }
  | _ => none

@[simp] theorem Evidence.ofVal_toVal (e : Evidence) : Evidence.ofVal e.toVal = some e := by
  cases e
  simp +decide [Evidence.ofVal, Evidence.toVal, getStr, lookupF]

/-- One edge of the domain graph. -/
structure Relation where
  /-- Where the edge starts. -/
  source : Id
  /-- What kind of edge. -/
  kind : Rel
  /-- Where it ends. -/
  target : Id
deriving Repr, Inhabited, DecidableEq

/-- A relation as a canonical value. -/
def Relation.toVal (r : Relation) : Val :=
  .obj [("source_id".toList, .str r.source), ("relation".toList, .str r.kind.name),
        ("target_id".toList, .str r.target)]

/-- A relation read back. -/
def Relation.ofVal : Val → Option Relation
  | .obj fs => do
      let source ← getStr fs "source_id".toList
      let kind ← (getStr fs "relation".toList).bind Rel.ofName
      let target ← getStr fs "target_id".toList
      pure { source, kind, target }
  | _ => none

@[simp] theorem Relation.ofVal_toVal (r : Relation) : Relation.ofVal r.toVal = some r := by
  cases r
  simp +decide [Relation.ofVal, Relation.toVal, getStr, lookupF]

/-- A schema the domain data is shaped by. -/
structure Schema where
  /-- The identifier of this schema. -/
  id : Id
  /-- Its name. -/
  name : List Char
  /-- Its version. -/
  version : List Char
  /-- Where it lives. -/
  location : List Char
deriving Inhabited, DecidableEq

/-- A schema as a canonical value. -/
def Schema.toVal (s : Schema) : Val :=
  .obj [("id".toList, .str s.id), ("name".toList, .str s.name),
        ("version".toList, .str s.version), ("location".toList, .str s.location)]

/-- A schema read back. -/
def Schema.ofVal : Val → Option Schema
  | .obj fs => do
      let id ← getStr fs "id".toList
      let name ← getStr fs "name".toList
      let version ← getStr fs "version".toList
      let location ← getStr fs "location".toList
      pure { id, name, version, location }
  | _ => none

@[simp] theorem Schema.ofVal_toVal (s : Schema) : Schema.ofVal s.toVal = some s := by
  cases s
  simp +decide [Schema.ofVal, Schema.toVal, getStr, lookupF]

/-! ## The domain -/

/-- The whole domain: the canonical graph every emitted representation is
a projection of. -/
structure Domain where
  /-- The identifier of the domain. -/
  id : Id
  /-- Its name. -/
  name : List Char
  /-- Its version. -/
  version : List Char
  /-- What it is. -/
  description : List Char
  /-- Its data objects. -/
  objects : List DomObj
  /-- The edges between them. -/
  relations : List Relation
  /-- The proof catalog. -/
  proofs : List ProofRec
  /-- The claims. -/
  claims : List Claim
  /-- The evidence. -/
  evidence : List Evidence
  /-- The schemas. -/
  schemas : List Schema
  /-- The errors, kept rather than thrown away. -/
  errors : List Err
  /-- Where all of it came from. -/
  provenance : List Prov
deriving Inhabited

/-- The domain as a canonical value. -/
def Domain.toVal (d : Domain) : Val :=
  .obj [("id".toList, .str d.id), ("name".toList, .str d.name),
        ("version".toList, .str d.version), ("description".toList, .str d.description),
        ("objects".toList, .list (d.objects.map DomObj.toVal)),
        ("relations".toList, .list (d.relations.map Relation.toVal)),
        ("proofs".toList, .list (d.proofs.map ProofRec.toVal)),
        ("claims".toList, .list (d.claims.map Claim.toVal)),
        ("evidence".toList, .list (d.evidence.map Evidence.toVal)),
        ("schemas".toList, .list (d.schemas.map Schema.toVal)),
        ("errors".toList, .list (d.errors.map Err.toVal)),
        ("provenance".toList, .list (d.provenance.map Prov.toVal))]

/-- The domain read back. -/
def Domain.ofVal : Val → Option Domain
  | .obj fs => do
      let id ← getStr fs "id".toList
      let name ← getStr fs "name".toList
      let version ← getStr fs "version".toList
      let description ← getStr fs "description".toList
      let objects ← (getList fs "objects".toList).bind (listOf DomObj.ofVal)
      let relations ← (getList fs "relations".toList).bind (listOf Relation.ofVal)
      let proofs ← (getList fs "proofs".toList).bind (listOf ProofRec.ofVal)
      let claims ← (getList fs "claims".toList).bind (listOf Claim.ofVal)
      let evidence ← (getList fs "evidence".toList).bind (listOf Evidence.ofVal)
      let schemas ← (getList fs "schemas".toList).bind (listOf Schema.ofVal)
      let errors ← (getList fs "errors".toList).bind (listOf Err.ofVal)
      let provenance ← (getList fs "provenance".toList).bind (listOf Prov.ofVal)
      pure { id, name, version, description, objects, relations, proofs, claims, evidence,
             schemas, errors, provenance }
  | _ => none

/-- **Nothing about a domain is lost in the canonical model.** -/
@[simp] theorem Domain.ofVal_toVal (d : Domain) : Domain.ofVal d.toVal = some d := by
  cases d
  simp +decide [Domain.ofVal, Domain.toVal, getStr, getList, lookupF,
    listOf_map DomObj.ofVal_toVal, listOf_map Relation.ofVal_toVal,
    listOf_map ProofRec.ofVal_toVal, listOf_map Claim.ofVal_toVal,
    listOf_map Evidence.ofVal_toVal, listOf_map Schema.ofVal_toVal,
    listOf_map Err.ofVal_toVal, listOf_map Prov.ofVal_toVal]

/-- **The canonical value determines the domain.** -/
theorem Domain.toVal_injective {a b : Domain} (h : a.toVal = b.toVal) : a = b := by
  have := congrArg Domain.ofVal h
  simpa using this

/-! ## Canonical hashes -/

/-- The canonical text of a domain object. -/
def DomObj.text (o : DomObj) : List Char := canonEnc o.toVal

/-- The canonical hash of a domain object: the witness of its canonical
bytes. -/
def DomObj.hash (o : DomObj) : List Char := valHash o.toVal

/-- The canonical hash of a proof record. -/
def ProofRec.hash (p : ProofRec) : List Char := valHash p.toVal

/-- The canonical text of a domain. -/
def Domain.text (d : Domain) : List Char := canonEnc d.toVal

/-- The canonical hash of a domain. -/
def Domain.hash (d : Domain) : List Char := valHash d.toVal

/-- **The canonical text determines the object**, so the hash is a content
identity and not a label. -/
theorem DomObj.eq_of_text_eq {a b : DomObj} (h : a.text = b.text) : a = b := by
  have hv : a.toVal = b.toVal := canonEnc_injective h
  have := congrArg DomObj.ofVal hv
  simpa using this

/-- **The canonical text determines the domain.** -/
theorem Domain.eq_of_text_eq {a b : Domain} (h : a.text = b.text) : a = b :=
  Domain.toVal_injective (canonEnc_injective h)

/-- Equal domains hash equally: the same object always presents the same
hash, in every representation. -/
theorem Domain.hash_eq_of_eq {a b : Domain} (h : a = b) : a.hash = b.hash := by rw [h]

/-- A domain hash is 64 characters wide. -/
@[simp] theorem Domain.hash_length (d : Domain) : d.hash.length = 64 := valHash_length _

/-- A domain-object hash is 64 characters wide. -/
@[simp] theorem DomObj.hash_length (o : DomObj) : o.hash.length = 64 := valHash_length _

/-- Different hashes mean different domains. -/
theorem Domain.ne_of_hash_ne {a b : Domain} (h : a.hash ≠ b.hash) : a ≠ b := by
  intro hab; exact h (Domain.hash_eq_of_eq hab)

end Kant.Dom
