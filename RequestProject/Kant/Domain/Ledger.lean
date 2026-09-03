/-
# The proof ledger, coverage, and the two-way walk between data and proof

A domain object does not say `proof: "proved"`.  It names proof records,
and the ledger is the index that resolves those names:

```text
object        claim        proof        status
------------------------------------------------
obj_001       claim_001    proof_001    VALID
obj_004       claim_004    --           UNPROVEN
```

Proved here:

* `coverage_proven_iff` — an object counts as `PROVEN` exactly when one of
  the proofs it names resolves and reports `VALID`;
* `proven_points_at_a_proof` — so a `PROVEN` row always has a proof
  identifier that resolves;
* `summary_total` — the coverage classes partition the objects, so the
  summary counts add up;
* `ledger_stable` — the ledger computed from any emitted representation is
  the ledger of the canonical domain;
* the traversal of §25 — `data_to_proof`, `proof_to_inputs`,
  `proof_to_outputs`, `output_to_data`, and `traversal_round_trip`, which
  walks `DATA → PROOF → OUTPUT → DATA` and lands back where it started.
-/
import Mathlib
import RequestProject.Kant.Domain.Emit

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.Dom

open Kant.Codec

/-! ## Resolution -/

/-- The proof record with this identifier, if the domain has one. -/
def findProof (d : Domain) (i : Id) : Option ProofRec := d.proofs.find? (fun p => p.id == i)

/-- The domain object with this identifier, if the domain has one. -/
def findObj (d : Domain) (i : Id) : Option DomObj := d.objects.find? (fun o => o.id == i)

/-- The claim with this identifier. -/
def findClaim (d : Domain) (i : Id) : Option Claim := d.claims.find? (fun c => c.id == i)

/-- The proofs an object names, as records — references that do not
resolve simply are not there, and `unresolved_refs` reports them. -/
def proofsOf (d : Domain) (o : DomObj) : List ProofRec := o.proofRefs.filterMap (findProof d)

/-- Proof references of an object that resolve to nothing. -/
def unresolvedRefs (d : Domain) (o : DomObj) : List Id :=
  o.proofRefs.filter (fun i => (findProof d i).isNone)

theorem findProof_id {d : Domain} {i : Id} {p : ProofRec} (h : findProof d i = some p) :
    p.id = i ∧ p ∈ d.proofs := by
  have hmem := List.find?_some h
  have hin := List.mem_of_find?_eq_some h
  exact ⟨by simpa using hmem, hin⟩

theorem mem_proofsOf {d : Domain} {o : DomObj} {p : ProofRec} (h : p ∈ proofsOf d o) :
    p.id ∈ o.proofRefs ∧ p ∈ d.proofs := by
  simp only [proofsOf, List.mem_filterMap] at h
  obtain ⟨i, hi, hf⟩ := h
  obtain ⟨hid, hmem⟩ := findProof_id hf
  exact ⟨hid ▸ hi, hmem⟩

/-! ## Coverage -/

/-- The proof coverage of one object, computed from the graph alone, so
that the classification is reproducible by anyone holding the package. -/
def coverage (d : Domain) (o : DomObj) : Coverage :=
  if o.truth = .contradicted ∨ o.truth = .invalid then .contradicted
  else if (proofsOf d o).any (fun p => p.status == .valid) then .proven
  else if (proofsOf d o).any (fun p => p.status == .«partial» || p.status == .unknown) then
    .partiallyProven
  else .unproven

/-- **An object is `PROVEN` exactly when one of the proofs it names
resolves and reports `VALID`** — and is not itself contradicted. -/
theorem coverage_proven_iff (d : Domain) (o : DomObj) :
    coverage d o = .proven ↔
      (o.truth ≠ .contradicted ∧ o.truth ≠ .invalid) ∧ ∃ p ∈ proofsOf d o, p.status = .valid := by
  unfold coverage
  by_cases hc : o.truth = .contradicted ∨ o.truth = .invalid
  · rw [if_pos hc]
    refine iff_of_false (by decide) ?_
    rintro ⟨⟨h1, h2⟩, -⟩
    rcases hc with h | h
    · exact h1 h
    · exact h2 h
  · rw [if_neg hc]
    push_neg at hc
    by_cases hv : (proofsOf d o).any (fun p => p.status == .valid) = true
    · rw [if_pos hv]
      simp only [List.any_eq_true, beq_iff_eq] at hv
      exact iff_of_true rfl ⟨hc, hv⟩
    · simp only [List.any_eq_true, beq_iff_eq, not_exists] at hv
      push_neg at hv
      rw [if_neg (by simpa using hv)]
      by_cases hp : (proofsOf d o).any (fun p => p.status == .«partial» || p.status == .unknown)
          = true
      · rw [if_pos hp]
        refine iff_of_false (by decide) ?_
        rintro ⟨-, q, hq, hst⟩
        exact hv q hq hst
      · rw [if_neg hp]
        refine iff_of_false (by decide) ?_
        rintro ⟨-, q, hq, hst⟩
        exact hv q hq hst

/-- **A `PROVEN` object always points at a proof that resolves.**  This is
the difference between `status = PROVEN` and evidence. -/
theorem proven_points_at_a_proof (d : Domain) (o : DomObj) (h : coverage d o = .proven) :
    ∃ i ∈ o.proofRefs, ∃ p, findProof d i = some p ∧ p.id = i ∧ p.status = .valid := by
  obtain ⟨-, p, hp, hst⟩ := (coverage_proven_iff d o).1 h
  simp only [proofsOf, List.mem_filterMap] at hp
  obtain ⟨i, hi, hf⟩ := hp
  exact ⟨i, hi, p, hf, (findProof_id hf).1, hst⟩

/-- An object with no proof at all is `UNPROVEN`, never `PROVEN`. -/
theorem no_proofs_unproven (d : Domain) (o : DomObj)
    (h : o.truth ≠ .contradicted) (h' : o.truth ≠ .invalid) (hp : proofsOf d o = []) :
    coverage d o = .unproven := by
  unfold coverage
  simp [h, h', hp]

/-! ## The ledger -/

/-- One line of the proof ledger. -/
structure LedgerRow where
  /-- The object this line is about. -/
  objectId : Id
  /-- The claim it makes, if it names one. -/
  claimId : Id
  /-- The proof establishing it, if one resolves. -/
  proofId : Id
  /-- The declared truth status of the object. -/
  truth : Truth
  /-- The status of the named proof. -/
  proofStatus : Option PStatus
  /-- The computed coverage class. -/
  coverage : Coverage
  /-- The canonical hash of the object. -/
  objectHash : List Char
deriving Repr

/-- The first entry of a list, or `--`. -/
def firstOr (xs : List Id) : Id :=
  match xs with
  | [] => "--".toList
  | x :: _ => x

/-- The proof a ledger line cites: a `VALID` one if there is one,
otherwise whichever resolves first. -/
def citedProof (d : Domain) (o : DomObj) : Option ProofRec :=
  match (proofsOf d o).find? (fun p => p.status == .valid) with
  | some p => some p
  | none => (proofsOf d o).head?

/-- One line of the ledger. -/
def ledgerRow (d : Domain) (o : DomObj) : LedgerRow :=
  { objectId := o.id
    claimId := firstOr o.claimRefs
    proofId := match citedProof d o with | some p => p.id | none => "--".toList
    truth := o.truth
    proofStatus := (citedProof d o).map ProofRec.status
    coverage := coverage d o
    objectHash := o.hash }

/-- The proof ledger: the authoritative index from domain knowledge to
formal evidence. -/
def ledger (d : Domain) : List LedgerRow := d.objects.map (ledgerRow d)

/-- **Every object is in the ledger, exactly once.** -/
@[simp] theorem ledger_length (d : Domain) : (ledger d).length = d.objects.length := by
  simp [ledger]

theorem mem_ledger (d : Domain) {o : DomObj} (h : o ∈ d.objects) : ledgerRow d o ∈ ledger d :=
  List.mem_map_of_mem h

/-- A proof reached through an object resolves under its own name. -/
theorem findProof_of_mem_proofsOf {d : Domain} {o : DomObj} {p : ProofRec}
    (h : p ∈ proofsOf d o) : findProof d p.id = some p := by
  simp only [proofsOf, List.mem_filterMap] at h
  obtain ⟨i, -, hf⟩ := h
  rw [(findProof_id hf).1, hf]

/-- **A ledger line that says `PROVEN` cites a proof that resolves and
reports `VALID`.**  The ledger cannot claim more than the graph. -/
theorem ledger_proven_sound (d : Domain) (o : DomObj)
    (h : (ledgerRow d o).coverage = .proven) :
    ∃ p, findProof d (ledgerRow d o).proofId = some p ∧ p.status = .valid ∧
      p.id ∈ o.proofRefs := by
  obtain ⟨-, q, hq, hqst⟩ := (coverage_proven_iff d o).1 (show coverage d o = .proven from h)
  obtain ⟨r, hr⟩ : ∃ r, (proofsOf d o).find? (fun p => p.status == .valid) = some r := by
    cases hf : (proofsOf d o).find? (fun p => p.status == .valid) with
    | none =>
        have hno := List.find?_eq_none.1 hf q hq
        simp [hqst] at hno
    | some r => exact ⟨r, rfl⟩
  have hrmem : r ∈ proofsOf d o := List.mem_of_find?_eq_some hr
  have hrst : r.status = .valid := by simpa using List.find?_some hr
  have hcited : citedProof d o = some r := by simp [citedProof, hr]
  refine ⟨r, ?_, hrst, (mem_proofsOf hrmem).1⟩
  have hpid : (ledgerRow d o).proofId = r.id := by simp [ledgerRow, hcited]
  rw [hpid]
  exact findProof_of_mem_proofsOf hrmem

/-- **A ledger line that cites no proof does not say `PROVEN`.** -/
theorem ledger_unproven_has_no_proof (d : Domain) (o : DomObj)
    (h : citedProof d o = none) : (ledgerRow d o).coverage ≠ .proven := by
  intro hc
  obtain ⟨-, q, hq, hqst⟩ := (coverage_proven_iff d o).1 (show coverage d o = .proven from hc)
  have : (proofsOf d o).head?.isSome := by
    cases hh : proofsOf d o with
    | nil => rw [hh] at hq; simp at hq
    | cons a as => simp
  rw [citedProof] at h
  rcases hf : (proofsOf d o).find? (fun p => p.status == .valid) with _ | r
  · rw [hf] at h
    rcases hh : (proofsOf d o) with _ | ⟨a, as⟩
    · rw [hh] at hq; simp at hq
    · rw [hh] at h; simp at h
  · rw [hf] at h; simp at h

/-! ## The coverage summary -/

/-- The counts the package reports. -/
structure Summary where
  /-- How many objects the domain has. -/
  objects : Nat
  /-- How many are proven. -/
  proven : Nat
  /-- How many are partially proven. -/
  partiallyProven : Nat
  /-- How many are unproven. -/
  unproven : Nat
  /-- How many are contradicted. -/
  contradicted : Nat
  /-- How many proof records there are. -/
  proofs : Nat
  /-- How many of them are `VALID`. -/
  validProofs : Nat
deriving Repr, DecidableEq

/-- The coverage summary of a domain. -/
def summary (d : Domain) : Summary :=
  { objects := d.objects.length
    proven := d.objects.countP (fun o => coverage d o == .proven)
    partiallyProven := d.objects.countP (fun o => coverage d o == .partiallyProven)
    unproven := d.objects.countP (fun o => coverage d o == .unproven)
    contradicted := d.objects.countP (fun o => coverage d o == .contradicted)
    proofs := d.proofs.length
    validProofs := d.proofs.countP (fun p => p.status == .valid) }

theorem countP_coverage_split (d : Domain) (l : List DomObj) :
    l.countP (fun o => coverage d o == .proven) +
      l.countP (fun o => coverage d o == .partiallyProven) +
      l.countP (fun o => coverage d o == .unproven) +
      l.countP (fun o => coverage d o == .contradicted) = l.length := by
  induction l with
  | nil => simp
  | cons a as ih =>
      simp only [List.countP_cons, List.length_cons]
      cases coverage d a <;> simp <;> omega

/-- **The coverage classification partitions the objects**: the summary
adds up, so no object is counted twice and none is left out. -/
theorem summary_total (d : Domain) :
    (summary d).proven + (summary d).partiallyProven + (summary d).unproven +
      (summary d).contradicted = (summary d).objects :=
  countP_coverage_split d d.objects

/-- **The ledger is a property of the graph, not of the file it came
from**: computed from any representation, it is the same ledger. -/
theorem ledger_stable (f : Fmt) (d : Domain) :
    (parse f (emit f d)).map ledger = some (ledger d) := by
  rw [parse_emit]; rfl

/-- **And so is the coverage summary.** -/
theorem summary_stable (f : Fmt) (d : Domain) :
    (parse f (emit f d)).map summary = some (summary d) := by
  rw [parse_emit]; rfl

/-! ## Well-formedness and the two-way walk -/

/-- What it means for a domain package to be internally consistent. -/
structure Wf (d : Domain) : Prop where
  /-- Object identifiers are unique, so a reference names one object. -/
  objectsNodup : (d.objects.map DomObj.id).Nodup
  /-- Proof identifiers are unique. -/
  proofsNodup : (d.proofs.map ProofRec.id).Nodup
  /-- Every proof an object names resolves, and agrees that it produced
  that object. -/
  proofRefsResolve : ∀ o ∈ d.objects, ∀ i ∈ o.proofRefs,
    ∃ p, findProof d i = some p ∧ o.id ∈ p.outputRefs
  /-- Everything a proof consumes is a domain object. -/
  inputsResolve : ∀ p ∈ d.proofs, ∀ i ∈ p.inputRefs, (findObj d i).isSome
  /-- Everything a proof produces is a domain object that names it back. -/
  outputsResolve : ∀ p ∈ d.proofs, ∀ i ∈ p.outputRefs,
    ∃ o, findObj d i = some o ∧ p.id ∈ o.proofRefs
  /-- **No silent claims**: an object may declare `PROVEN` only if a proof
  record that resolves reports `VALID`. -/
  provenIsProved : ∀ o ∈ d.objects, o.truth = .proven →
    ∃ i ∈ o.proofRefs, ∃ p, findProof d i = some p ∧ p.status = .valid

theorem find?_byId {α : Type} (idOf : α → Id) {l : List α} (hn : (l.map idOf).Nodup)
    {a : α} (ha : a ∈ l) : l.find? (fun x => idOf x == idOf a) = some a := by
  induction l with
  | nil => simp at ha
  | cons b bs ih =>
      simp only [List.map_cons, List.nodup_cons, List.mem_map] at hn
      rcases List.mem_cons.1 ha with rfl | hmem
      · rw [List.find?_cons_of_pos (by simp)]
      · have hne : ¬ (idOf b = idOf a) := fun h => hn.1 ⟨a, hmem, h.symm⟩
        rw [List.find?_cons_of_neg (by simpa using hne)]
        exact ih hn.2 hmem

theorem find?_id_of_mem {l : List DomObj} (hn : (l.map DomObj.id).Nodup) {o : DomObj}
    (ho : o ∈ l) : l.find? (fun x => x.id == o.id) = some o :=
  find?_byId DomObj.id hn ho

/-- An object with a unique identifier is found under it. -/
theorem findObj_of_mem {d : Domain} (hn : (d.objects.map DomObj.id).Nodup) {o : DomObj}
    (ho : o ∈ d.objects) : findObj d o.id = some o :=
  find?_byId DomObj.id hn ho

/-- A proof record with a unique identifier is found under it. -/
theorem findProof_of_mem {d : Domain} (hn : (d.proofs.map ProofRec.id).Nodup) {p : ProofRec}
    (hp : p ∈ d.proofs) : findProof d p.id = some p :=
  find?_byId ProofRec.id hn hp

/-- In a well-formed domain an object is found under its own name. -/
theorem findObj_self {d : Domain} (hw : Wf d) {o : DomObj} (ho : o ∈ d.objects) :
    findObj d o.id = some o :=
  find?_id_of_mem hw.objectsNodup ho

/-- **DATA → PROOF.**  A proven object names a proof that resolves, says
`VALID`, and lists that object among its outputs. -/
theorem data_to_proof {d : Domain} (hw : Wf d) {o : DomObj} (ho : o ∈ d.objects)
    (h : o.truth = .proven) :
    ∃ i ∈ o.proofRefs, ∃ p, findProof d i = some p ∧ p.status = .valid ∧ o.id ∈ p.outputRefs := by
  obtain ⟨i, hi, p, hp, hst⟩ := hw.provenIsProved o ho h
  obtain ⟨q, hq, hout⟩ := hw.proofRefsResolve o ho i hi
  have : p = q := by rw [hp] at hq; exact Option.some.inj hq
  subst this
  exact ⟨i, hi, p, hp, hst, hout⟩

/-- **PROOF → INPUTS.**  Everything a proof consumes is a domain object. -/
theorem proof_to_inputs {d : Domain} (hw : Wf d) {p : ProofRec} (hp : p ∈ d.proofs)
    {i : Id} (hi : i ∈ p.inputRefs) : ∃ o, findObj d i = some o := by
  have := hw.inputsResolve p hp i hi
  exact Option.isSome_iff_exists.1 this

/-- **PROOF → OUTPUTS.**  Everything a proof produces is a domain object
that names the proof back. -/
theorem proof_to_outputs {d : Domain} (hw : Wf d) {p : ProofRec} (hp : p ∈ d.proofs)
    {i : Id} (hi : i ∈ p.outputRefs) :
    ∃ o, findObj d i = some o ∧ p.id ∈ o.proofRefs := hw.outputsResolve p hp i hi

/-- **OUTPUT → DATA.**  The object an output names is the object it came
from: walking `DATA → PROOF → OUTPUT → DATA` returns to the start. -/
theorem traversal_round_trip {d : Domain} (hw : Wf d) {o : DomObj} (ho : o ∈ d.objects)
    (h : o.truth = .proven) :
    ∃ p, p ∈ d.proofs ∧ p.status = .valid ∧ o.id ∈ p.outputRefs ∧
      findObj d o.id = some o ∧ p.id ∈ o.proofRefs := by
  obtain ⟨i, hi, p, hp, hst, hout⟩ := data_to_proof hw ho h
  obtain ⟨hid, hmem⟩ := findProof_id hp
  obtain ⟨o', ho', hback⟩ := hw.outputsResolve p hmem o.id hout
  have hoo : o' = o := by
    rw [findObj_self hw ho] at ho'
    exact (Option.some.inj ho').symm
  subst hoo
  exact ⟨p, hmem, hst, hout, findObj_self hw ho, hback⟩

/-- **A proven object is never bare**: it always names at least one
proof. -/
theorem proven_not_bare {d : Domain} (hw : Wf d) {o : DomObj} (ho : o ∈ d.objects)
    (h : o.truth = .proven) : o.proofRefs ≠ [] := by
  obtain ⟨i, hi, -⟩ := hw.provenIsProved o ho h
  intro hnil
  rw [hnil] at hi
  simp at hi

/-! ## Relations mirror the proof catalog -/

/-- The edges implied by the proof catalog: what each proof consumes, what
it produces, what it depends on. -/
def derivedRelations (d : Domain) : List Relation :=
  d.proofs.flatMap (fun p =>
    p.inputRefs.map (fun i => ⟨i, .inputTo, p.id⟩) ++
    p.outputRefs.map (fun o => ⟨o, .outputOf, p.id⟩) ++
    p.outputRefs.map (fun o => ⟨p.id, .proves, o⟩) ++
    p.outputRefs.map (fun o => ⟨o, .provenBy, p.id⟩) ++
    p.dependsOn.map (fun q => ⟨p.id, .dependsOn, q⟩))

/-- **What a proof produces shows up as an edge both ways.** -/
theorem derived_proves {d : Domain} {p : ProofRec} (hp : p ∈ d.proofs) {o : Id}
    (ho : o ∈ p.outputRefs) :
    (⟨p.id, .proves, o⟩ : Relation) ∈ derivedRelations d ∧
      (⟨o, .provenBy, p.id⟩ : Relation) ∈ derivedRelations d := by
  constructor <;>
    · simp only [derivedRelations, List.mem_flatMap]
      exact ⟨p, hp, by simp [ho]⟩

/-- **What a proof consumes shows up as an edge.** -/
theorem derived_input {d : Domain} {p : ProofRec} (hp : p ∈ d.proofs) {i : Id}
    (hi : i ∈ p.inputRefs) : (⟨i, .inputTo, p.id⟩ : Relation) ∈ derivedRelations d := by
  simp only [derivedRelations, List.mem_flatMap]
  exact ⟨p, hp, by simp [hi]⟩

/-- Canonicalization: the relations table filled in from the catalog. -/
def withDerivedRelations (d : Domain) : Domain := { d with relations := derivedRelations d }

/-- Canonicalization changes nothing but the relations table. -/
@[simp] theorem withDerivedRelations_objects (d : Domain) :
    (withDerivedRelations d).objects = d.objects := rfl

@[simp] theorem withDerivedRelations_proofs (d : Domain) :
    (withDerivedRelations d).proofs = d.proofs := rfl

/-- Coverage does not depend on the relations table, so canonicalizing it
cannot change what counts as proven. -/
@[simp] theorem coverage_withDerivedRelations (d : Domain) (o : DomObj) :
    coverage (withDerivedRelations d) o = coverage d o := rfl

end Kant.Dom
