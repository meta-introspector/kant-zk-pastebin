/-
# The proof catalog

§7: *every proof with inputs and outputs becomes a catalog entry.*  This
module is the discovery step, as a function: a list of declarations as a
scanner found them in a corpus — name, kind, file, line, statement,
whether the source still contains a `sorry`, whether the checked axioms
are the standard ones, and which other declarations it mentions — becomes
a canonical domain.

```text
Decl  ──►  DomObj  ──proof_refs──►  ProofRec  ──output_refs──►  DomObj
```

Proved here:

* `catalog_wf` — the catalog is a well-formed graph: identifiers are
  unique, every reference resolves, every proof lists the object it
  produces and every object lists the proof that produced it, so the
  two-way walk of §25 works on it;
* `sorried_not_proven` and `catalog_no_silent_claim` — a declaration whose
  source still contains a `sorry`, or which rests on a non-standard axiom,
  never lands on `PROVEN`;
* `catalog_coverage_proven` — and one that is sorry-free and standard does,
  with a `VALID` proof record and a machine-checked certificate behind it.
-/
import Mathlib
import RequestProject.Kant.Domain.Table

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.Dom

open Kant.Codec

/-! ## Declarations -/

/-- One declaration, as a scanner of the corpus found it. -/
structure Decl where
  /-- Its fully qualified name. -/
  name : List Char
  /-- `theorem`, `lemma`, `def`, `structure`, … -/
  kind : List Char
  /-- The file it lives in. -/
  file : List Char
  /-- The line it starts on. -/
  line : Nat
  /-- Its statement, as text. -/
  statement : List Char
  /-- Whether its source still contains a `sorry`. -/
  sorried : Bool
  /-- Whether the axioms it was checked against are the standard ones. -/
  axiomsOk : Bool
  /-- The other declarations it mentions. -/
  deps : List (List Char)
deriving Inhabited, DecidableEq

/-- The identifier of the domain object for a declaration. -/
def objId (n : List Char) : Id := "obj.".toList ++ n

/-- The identifier of the proof record for a declaration. -/
def proofIdOf (n : List Char) : Id := "proof.".toList ++ n

/-- The identifier of the claim record for a declaration. -/
def claimIdOf (n : List Char) : Id := "claim.".toList ++ n

theorem objId_injective {a b : List Char} (h : objId a = objId b) : a = b := by
  simpa [objId] using h

theorem proofIdOf_injective {a b : List Char} (h : proofIdOf a = proofIdOf b) : a = b := by
  simpa [proofIdOf] using h

/-- Whether a declaration is a proof of something. -/
def Decl.isProof (d : Decl) : Bool := d.kind == "theorem".toList || d.kind == "lemma".toList

/-- What the proof record for a declaration reports.  A `sorry` makes it
`PARTIAL`; a non-standard axiom makes it `UNKNOWN`; otherwise the kernel
checked it and it is `VALID`. -/
def Decl.status (d : Decl) : PStatus :=
  if d.sorried then .«partial» else if d.axiomsOk then .valid else .unknown

/-- The truth status of the object a declaration stands for.  Only a
sorry-free proof checked against the standard axioms is `PROVEN`; a
definition is `ASSERTED`, because a definition is a stipulation. -/
def Decl.truth (d : Decl) : Truth :=
  if d.isProof then
    (if d.sorried then .unresolved else if d.axiomsOk then .proven else .unresolved)
  else .asserted

/-- A corpus is *closed* when every dependency a declaration records is
itself a declaration of the corpus.  A scanner produces a closed corpus by
dropping references to anything outside the scope it is emitting. -/
def Closed (ds : List Decl) : Prop :=
  ∀ d ∈ ds, ∀ n ∈ d.deps, n ∈ ds.map Decl.name

/-- Where a declaration came from. -/
def declProv (d : Decl) : Prov :=
  { sourceSystem := "lean4".toList, sourceFile := d.file, sourceFormat := .text,
    importedAt := 0, transformedAt := d.line, transformations := [], parent := [] }

/-- The domain object a declaration stands for. -/
def declObject (d : Decl) : DomObj :=
  { id := objId d.name
    kind := d.kind
    name := d.name
    value := .str d.statement
    claim := d.statement
    inputs := d.deps.map objId
    parameters := []
    transformations := []
    outputs := []
    claimRefs := if d.isProof then [claimIdOf d.name] else []
    evidenceRefs := []
    proofRefs := if d.isProof then [proofIdOf d.name] else []
    errorRefs := []
    truth := d.truth
    provenance := some (declProv d) }

/-- The certificate of a declaration: the kernel checked it, and the
digest is the witness of its statement.  A `sorry` means there is no
certificate at all. -/
def declCert (d : Decl) : Option Cert :=
  if d.sorried then none
  else some { kind := "lean4-kernel".toList, digest := valHash (.str d.statement),
              location := d.file, evidence := if d.axiomsOk then .machineChecked else .stated }

/-- The proof record for a declaration. -/
def declProof (d : Decl) : ProofRec :=
  { id := proofIdOf d.name
    name := d.name
    kind := "lean4".toList
    sourceFile := d.file
    sourceLoc := natDigits d.line
    inputRefs := d.deps.map objId
    assumptions := []
    procedure := "elaborated and checked by the Lean kernel".toList
    outputRefs := [objId d.name]
    claimRefs := [claimIdOf d.name]
    dependsOn := d.deps.map proofIdOf
    status := d.status
    certificate := declCert d
    source := "RequestProject".toList
    provenance := some (declProv d) }

/-- The claim a proof declaration establishes. -/
def declClaim (d : Decl) : Claim :=
  { id := claimIdOf d.name, objectRef := objId d.name, text := d.statement,
    truth := d.truth, proofRefs := [proofIdOf d.name] }

/-! ## A scan as data

The discovery step writes what it found as a canonical value, so the scan
of a corpus is itself an object of the model — it round-trips, and the
tool that emits a package need not be the tool that scanned. -/

/-- A declaration as a canonical value. -/
def Decl.toVal (d : Decl) : Val :=
  .obj [("name".toList, .str d.name), ("kind".toList, .str d.kind),
        ("file".toList, .str d.file), ("line".toList, .int d.line),
        ("statement".toList, .str d.statement), ("sorried".toList, .bool d.sorried),
        ("axioms_ok".toList, .bool d.axiomsOk), ("deps".toList, idsVal d.deps)]

/-- A declaration read back. -/
def Decl.ofVal : Val → Option Decl
  | .obj fs => do
      let name ← getStr fs "name".toList
      let kind ← getStr fs "kind".toList
      let file ← getStr fs "file".toList
      let line ← getNat fs "line".toList
      let statement ← getStr fs "statement".toList
      let sorried ← getBool fs "sorried".toList
      let axiomsOk ← getBool fs "axioms_ok".toList
      let deps ← getIds fs "deps".toList
      pure { name, kind, file, line, statement, sorried, axiomsOk, deps }
  | _ => none

@[simp] theorem Decl.ofVal_toVal (d : Decl) : Decl.ofVal d.toVal = some d := by
  cases d
  simp +decide [Decl.ofVal, Decl.toVal, getStr, getNat, getBool, getIds, getList, lookupF, idsVal]

/-- A whole scan as a canonical value. -/
def scanVal (ds : List Decl) : Val := .list (ds.map Decl.toVal)

/-- A scan read back. -/
def scanOfVal : Val → Option (List Decl)
  | .list xs => listOf Decl.ofVal xs
  | _ => none

/-- **A scan round-trips**, so the discovery step and the emission step
can be different programs. -/
@[simp] theorem scanOfVal_scanVal (ds : List Decl) : scanOfVal (scanVal ds) = some ds := by
  simp [scanOfVal, scanVal, listOf_map Decl.ofVal_toVal]

/-- **And it round-trips through its file**, which is canonical text. -/
theorem scan_file_roundTrip (ds : List Decl) :
    (canonDecode (canonEnc (scanVal ds))).bind scanOfVal = some ds := by
  simp [canonDecode_canonEnc]

/-! ## The catalog -/

/-- The domain a scanned corpus amounts to: one object per declaration,
one proof record and one claim per proof, and the relations implied by
the catalog. -/
def catalog (domainId : List Char) (description : List Char) (ds : List Decl) : Domain :=
  withDerivedRelations
    { id := domainId
      name := domainId
      version := "domain/1.0".toList
      description
      objects := ds.map (declObject)
      relations := []
      proofs := (ds.filter Decl.isProof).map (declProof)
      claims := (ds.filter Decl.isProof).map declClaim
      evidence := []
      schemas := []
      errors := []
      provenance := [{ sourceSystem := "lean4".toList, sourceFile := "RequestProject".toList,
                       sourceFormat := .text, importedAt := 0, transformedAt := 0,
                       transformations := [], parent := [] }] }

@[simp] theorem catalog_objects (cid desc : List Char) (ds : List Decl) :
    (catalog cid desc ds).objects = ds.map declObject := rfl

@[simp] theorem catalog_proofs (cid desc : List Char) (ds : List Decl) :
    (catalog cid desc ds).proofs = (ds.filter Decl.isProof).map (declProof) :=
  rfl

/-! ## The catalog is a well-formed graph -/

theorem objects_nodup {ds : List Decl} (hn : (ds.map Decl.name).Nodup) :
    (((catalog "d".toList [] ds).objects).map DomObj.id).Nodup := by
  simp only [catalog_objects, List.map_map]
  have : (DomObj.id ∘ declObject) = fun d => objId d.name := rfl
  rw [this]
  have hmap : (ds.map fun d => objId d.name) = (ds.map Decl.name).map objId := by
    simp [List.map_map, Function.comp]
  rw [hmap]
  exact hn.map (fun _ _ h => objId_injective h)

theorem proofs_nodup {ds : List Decl} (hn : (ds.map Decl.name).Nodup) :
    (((catalog "d".toList [] ds).proofs).map ProofRec.id).Nodup := by
  simp only [catalog_proofs, List.map_map]
  have : (ProofRec.id ∘ declProof) = fun d => proofIdOf d.name := rfl
  rw [this]
  have hmap : ((ds.filter Decl.isProof).map fun d => proofIdOf d.name)
      = ((ds.filter Decl.isProof).map Decl.name).map proofIdOf := by
    simp [List.map_map, Function.comp]
  rw [hmap]
  refine List.Nodup.map (fun _ _ h => proofIdOf_injective h) ?_
  have hsub : (ds.filter Decl.isProof).Sublist ds := List.filter_sublist
  exact (List.Sublist.map Decl.name hsub).nodup hn

/-- Every declaration of the corpus is found under the object identifier
built from its name. -/
theorem findObj_catalog {ds : List Decl} (hn : (ds.map Decl.name).Nodup) {d : Decl}
    (hd : d ∈ ds) (cid desc : List Char) :
    findObj (catalog cid desc ds) (objId d.name)
      = some (declObject d) := by
  have hmem : declObject d ∈ (catalog cid desc ds).objects := by
    simp only [catalog_objects]
    exact List.mem_map_of_mem hd
  have hnodup : (((catalog cid desc ds).objects).map DomObj.id).Nodup := by
    have := objects_nodup (ds := ds) hn
    simpa using this
  exact findObj_of_mem hnodup hmem

/-- Every proof declaration is found under the proof identifier built from
its name. -/
theorem findProof_catalog {ds : List Decl} (hn : (ds.map Decl.name).Nodup) {d : Decl}
    (hd : d ∈ ds) (hp : d.isProof = true) (cid desc : List Char) :
    findProof (catalog cid desc ds) (proofIdOf d.name)
      = some (declProof d) := by
  have hmem : declProof d ∈ (catalog cid desc ds).proofs := by
    simp only [catalog_proofs]
    exact List.mem_map_of_mem (List.mem_filter.2 ⟨hd, hp⟩)
  have hnodup : (((catalog cid desc ds).proofs).map ProofRec.id).Nodup := by
    have := proofs_nodup (ds := ds) hn
    simpa using this
  exact findProof_of_mem hnodup hmem

/-- Membership of a name gives the declaration that carries it. -/
theorem decl_of_name {ds : List Decl} {n : List Char} (h : n ∈ ds.map Decl.name) :
    ∃ d ∈ ds, d.name = n := by
  simpa using h

/-- **The catalog is a well-formed domain graph.**  Identifiers are
unique, every reference resolves, and the walk from a proven object to its
proof and back to the object works. -/
theorem catalog_wf {ds : List Decl} (hn : (ds.map Decl.name).Nodup) (hc : Closed ds)
    (cid desc : List Char) : Wf (catalog cid desc ds) := by
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_⟩
  · have := objects_nodup (ds := ds) hn; simpa using this
  · have := proofs_nodup (ds := ds) hn; simpa using this
  · intro o ho i hi
    simp only [catalog_objects, List.mem_map] at ho
    obtain ⟨d, hd, rfl⟩ := ho
    by_cases hpf : d.isProof = true
    · simp only [declObject, if_pos hpf, List.mem_singleton] at hi
      subst hi
      refine ⟨declProof d, findProof_catalog hn hd hpf cid desc, ?_⟩
      simp [declProof, declObject]
    · simp [declObject, hpf] at hi
  · intro p hp i hi
    simp only [catalog_proofs, List.mem_map] at hp
    obtain ⟨d, hd, rfl⟩ := hp
    simp only [declProof, List.mem_map] at hi
    obtain ⟨n, hnmem, rfl⟩ := hi
    obtain ⟨e, he, rfl⟩ := decl_of_name (hc d (List.mem_filter.1 hd).1 n hnmem)
    rw [findObj_catalog hn he cid desc]
    simp
  · intro p hp i hi
    simp only [catalog_proofs, List.mem_map] at hp
    obtain ⟨d, hd, rfl⟩ := hp
    have hdp : d.isProof = true := (List.mem_filter.1 hd).2
    simp only [declProof, List.mem_singleton] at hi
    subst hi
    refine ⟨declObject d,
      findObj_catalog hn (List.mem_filter.1 hd).1 cid desc, ?_⟩
    simp [declObject, declProof, hdp]
  · intro o ho ht
    simp only [catalog_objects, List.mem_map] at ho
    obtain ⟨d, hd, rfl⟩ := ho
    have hdp : d.isProof = true := by
      by_contra hc
      simp [declObject, Decl.truth, hc] at ht
    have hs : d.sorried = false ∧ d.axiomsOk = true := by
      by_cases h1 : d.sorried
      · simp [declObject, Decl.truth, hdp, h1] at ht
      · by_cases h2 : d.axiomsOk
        · exact ⟨by simpa using h1, h2⟩
        · simp [declObject, Decl.truth, hdp, h1, h2] at ht
    refine ⟨proofIdOf d.name, by simp [declObject, hdp], declProof d,
      findProof_catalog hn hd hdp cid desc, ?_⟩
    simp [declProof, Decl.status, hs.1, hs.2]

/-! ## No silent claims in the catalog -/

/-- **A declaration whose source still contains a `sorry` is never
`PROVEN`.** -/
theorem sorried_not_proven (d : Decl) (h : d.sorried = true) :
    (declObject d).truth ≠ .proven := by
  by_cases hp : d.isProof = true <;> simp [declObject, Decl.truth, h, hp]

/-- **Neither is one that rests on a non-standard axiom.** -/
theorem nonstandard_axioms_not_proven (d : Decl) (h : d.axiomsOk = false) : (declObject d).truth ≠ .proven := by
  by_cases hp : d.isProof = true <;> by_cases hs : d.sorried = true <;>
    simp [declObject, Decl.truth, h, hp, hs]

/-- **A `sorry` leaves no certificate.**  There is nothing to point at, so
nothing is pointed at. -/
theorem sorried_has_no_certificate (d : Decl) (h : d.sorried = true) : (declProof d).certificate = none := by
  simp [declProof, declCert, h]

/-- **And a sorry-free declaration checked against the standard axioms is
`PROVEN`, with a `VALID`, machine-checked proof record behind it.** -/
theorem catalog_coverage_proven {ds : List Decl} (hn : (ds.map Decl.name).Nodup) {d : Decl}
    (hd : d ∈ ds) (hp : d.isProof = true) (hs : d.sorried = false) (ha : d.axiomsOk = true)
    (cid desc : List Char) :
    (declObject d).truth = .proven ∧
      coverage (catalog cid desc ds) (declObject d) = .proven ∧
      (declProof d).status = .valid ∧
      (declProof d).certificate =
        some { kind := "lean4-kernel".toList, digest := valHash (.str d.statement),
               location := d.file, evidence := .machineChecked } := by
  have htruth : (declObject d).truth = .proven := by
    simp [declObject, Decl.truth, hp, hs, ha]
  have hstatus : (declProof d).status = .valid := by
    simp [declProof, Decl.status, hs, ha]
  refine ⟨htruth, ?_, hstatus, by simp [declProof, declCert, hs, ha]⟩
  rw [coverage_proven_iff]
  refine ⟨⟨by rw [htruth]; decide, by rw [htruth]; decide⟩,
    declProof d, ?_, hstatus⟩
  simp only [proofsOf, List.mem_filterMap]
  exact ⟨proofIdOf d.name, by simp [declObject, hp], findProof_catalog hn hd hp cid desc⟩

/-- **The whole corpus is covered**: every declaration appears in the
ledger exactly once. -/
theorem catalog_ledger_length {ds : List Decl} (cid desc : List Char) :
    (ledger (catalog cid desc ds)).length = ds.length := by
  simp [ledger]

end Kant.Dom
