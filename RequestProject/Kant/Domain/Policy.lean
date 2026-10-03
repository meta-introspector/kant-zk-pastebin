/-
# No silent claims, and errors that stay visible

Two rules of the standard are enforced here rather than described.

**§22.**  `ASSERTED`, `IMPORTED` and `INFERRED` never become `PROVEN`
without a validation event carrying a proof record that resolves and
reports `VALID` (`no_silent_upgrade`, `assertion_never_upgrades`).  And a
value that goes from `PROVEN` to `INVALID` or `CONTRADICTED` always emits
an explicit error (`downgrade_is_reported`).

**§21.**  A repair is not a silent edit: the error that prompted it stays
in the package, carrying what was expected, what arrived, what was done
about it, and whether the result revalidated (`repair_keeps_the_error`,
`unresolved_stays_visible`).
-/
import Mathlib
import RequestProject.Kant.Domain.Ledger

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.Dom

open Kant.Codec

/-! ## Events -/

/-- Something that happens to a domain value.  A truth status changes only
in response to one of these. -/
inductive Event
  /-- A proof record was checked and reported `VALID`. -/
  | validated (proofId : Id)
  /-- An independent system reproduced a proof. -/
  | reproduced (proofId : Id)
  /-- The value was derived by a proof that does not fully establish it. -/
  | derivedBy (proofId : Id)
  /-- Somebody wrote it down. -/
  | assertedBy (who : List Char)
  /-- It arrived from another system. -/
  | importedFrom (source : List Char)
  /-- It was inferred without proof. -/
  | inferredBy (how : List Char)
  /-- A proof record contradicts it. -/
  | contradiction (proofId : Id)
  /-- A validation failed. -/
  | invalidation (proofId : Id)
  /-- Nothing happened. -/
  | nothing
deriving Repr, Inhabited, DecidableEq

/-- A bare error record with the fields a policy event fills in. -/
def policyErr (code message objectId : List Char) (sev : Severity) : Err :=
  { id := code, code, severity := sev, message, location := "policy".toList,
    field := "truth.status".toList, objectId, sourceSystem := "kant-domain".toList,
    sourceFormat := .canonical, expected := [], actual := [], cause := [], resolution := [],
    recoverable := true }

/-- Whether an event carries a proof record that resolves and reports
`VALID`. -/
def validates (d : Domain) : Event → Bool
  | .validated i => match findProof d i with
      | some p => p.status == .valid
      | none => false
  | _ => false

/-- The truth status after an event, and the error the event records.
Nothing here can raise a status to `PROVEN` except a validation carrying a
`VALID` proof; nothing can lower one from `PROVEN` without an error. -/
def step (d : Domain) (objectId : Id) (e : Event) (t : Truth) : Truth × Option Err :=
  match e with
  | .validated i =>
      match findProof d i with
      | some p =>
          if p.status = .valid then (.proven, none)
          else (t, some (policyErr "UPGRADE_REFUSED".toList
                  "the cited proof does not report VALID".toList objectId .warning))
      | none => (t, some (policyErr "UNRESOLVED_PROOF_REF".toList
                  "the cited proof is not in the catalog".toList objectId .error))
  | .reproduced i =>
      match findProof d i with
      | some p => if p.status = .valid then (.verified, none)
          else (t, some (policyErr "UPGRADE_REFUSED".toList
                  "the reproduced proof does not report VALID".toList objectId .warning))
      | none => (t, some (policyErr "UNRESOLVED_PROOF_REF".toList
                  "the cited proof is not in the catalog".toList objectId .error))
  | .derivedBy i =>
      match findProof d i with
      | some _ => (.derived, none)
      | none => (t, some (policyErr "UNRESOLVED_PROOF_REF".toList
                  "the cited proof is not in the catalog".toList objectId .error))
  | .assertedBy _ => (.asserted, none)
  | .importedFrom _ => (.imported, none)
  | .inferredBy _ => (.inferred, none)
  | .contradiction _ =>
      (.contradicted, some (policyErr "CONTRADICTION".toList
        "a proof record contradicts this value".toList objectId
        (if t = .proven then .fatal else .error)))
  | .invalidation _ =>
      (.invalid, some (policyErr "VALIDATION_FAILED".toList
        "validation of this value failed".toList objectId
        (if t = .proven then .fatal else .error)))
  | .nothing => (t, none)

/-- **No silent claims.**  A value that was not already `PROVEN` becomes
`PROVEN` only through a validation event naming a proof record that is in
the catalog and reports `VALID`. -/
theorem no_silent_upgrade (d : Domain) (oid : Id) (e : Event) (t : Truth)
    (ht : t ≠ .proven) (h : (step d oid e t).1 = .proven) :
    ∃ i p, e = .validated i ∧ findProof d i = some p ∧ p.status = .valid := by
  cases e with
  | validated i =>
      rcases hf : findProof d i with _ | p
      · simp only [step, hf] at h; exact absurd h ht
      · by_cases hs : p.status = .valid
        · exact ⟨i, p, rfl, hf, hs⟩
        · simp only [step, hf, if_neg hs] at h; exact absurd h ht
  | reproduced i =>
      rcases hf : findProof d i with _ | p
      · simp only [step, hf] at h; exact absurd h ht
      · by_cases hs : p.status = .valid
        · simp only [step, hf, if_pos hs] at h; exact absurd h (by decide)
        · simp only [step, hf, if_neg hs] at h; exact absurd h ht
  | derivedBy i =>
      rcases hf : findProof d i with _ | p
      · simp only [step, hf] at h; exact absurd h ht
      · simp only [step, hf] at h; exact absurd h (by decide)
  | assertedBy w => simp only [step] at h; exact absurd h (by decide)
  | importedFrom s => simp only [step] at h; exact absurd h (by decide)
  | inferredBy w => simp only [step] at h; exact absurd h (by decide)
  | contradiction i => simp only [step] at h; exact absurd h (by decide)
  | invalidation i => simp only [step] at h; exact absurd h (by decide)
  | nothing => simp only [step] at h; exact absurd h ht

/-- **`ASSERTED → PROVEN`, `IMPORTED → PROVEN` and `INFERRED → PROVEN` do
not happen by assertion.**  Writing something down, importing it or
inferring it leaves it exactly where it was in the truth order. -/
theorem assertion_never_upgrades (d : Domain) (oid : Id) (t : Truth) (who : List Char) :
    (step d oid (.assertedBy who) t).1 = .asserted ∧
      (step d oid (.importedFrom who) t).1 = .imported ∧
      (step d oid (.inferredBy who) t).1 = .inferred :=
  ⟨rfl, rfl, rfl⟩

/-- **A refused upgrade is recorded.**  When the cited proof does not
resolve, or does not report `VALID`, the status does not move and an error
is attached. -/
theorem refusal_recorded (d : Domain) (oid : Id) (i : Id) (t : Truth)
    (h : validates d (.validated i) = false) :
    (step d oid (.validated i) t).1 = t ∧ (step d oid (.validated i) t).2.isSome := by
  rcases hf : findProof d i with _ | p
  · simp [step, hf]
  · have hs : ¬ p.status = .valid := by
      simp only [validates, hf, beq_eq_false_iff_ne, ne_eq] at h
      exact h
    simp [step, hf, hs]

/-- **`PROVEN → INVALID` and `PROVEN → CONTRADICTED` are always
reported.**  A value leaving `PROVEN` carries a fatal error saying so. -/
theorem downgrade_is_reported (d : Domain) (oid : Id) (e : Event)
    (h : (step d oid e .proven).1 = .invalid ∨ (step d oid e .proven).1 = .contradicted) :
    ∃ err, (step d oid e .proven).2 = some err ∧ err.severity = .fatal := by
  cases e with
  | validated i =>
      rcases hf : findProof d i with _ | p
      · simp only [step, hf] at h; simp at h
      · by_cases hs : p.status = .valid
        · simp only [step, hf, if_pos hs] at h; simp at h
        · simp only [step, hf, if_neg hs] at h; simp at h
  | reproduced i =>
      rcases hf : findProof d i with _ | p
      · simp only [step, hf] at h; simp at h
      · by_cases hs : p.status = .valid
        · simp only [step, hf, if_pos hs] at h; simp at h
        · simp only [step, hf, if_neg hs] at h; simp at h
  | derivedBy i =>
      rcases hf : findProof d i with _ | p
      · simp only [step, hf] at h; simp at h
      · simp only [step, hf] at h; simp at h
  | assertedBy w => simp [step] at h
  | importedFrom s => simp [step] at h
  | inferredBy w => simp [step] at h
  | contradiction i => exact ⟨_, rfl, rfl⟩
  | invalidation i => exact ⟨_, rfl, rfl⟩
  | nothing => simp [step] at h

/-- The event never invents a proof reference: the only status that can
follow a validation of a `VALID` proof is `PROVEN`, and it is exactly the
one the ledger will then be able to justify. -/
theorem validated_matches_ledger (d : Domain) (oid i : Id) (t : Truth) {p : ProofRec}
    (hf : findProof d i = some p) (hs : p.status = .valid) :
    (step d oid (.validated i) t).1 = .proven ∧ (step d oid (.validated i) t).2 = none := by
  simp [step, hf, hs]

/-! ## Error reconciliation -/

/-- What was done about an error. -/
inductive Repair
  /-- A string was read as the integer the schema declares. -/
  | stringToInteger
  /-- A missing optional field was filled with its declared default. -/
  | defaultApplied
  /-- Nothing could be done. -/
  | unresolved
deriving Repr, Inhabited, DecidableEq

/-- The wire name of a repair. -/
def Repair.name : Repair → List Char
  | .stringToInteger => "STRING_TO_INTEGER".toList
  | .defaultApplied => "DEFAULT_APPLIED".toList
  | .unresolved => "UNRESOLVED".toList

/-- One line of the transformation ledger: the error, what was done, and
whether the result revalidated. -/
structure RepairRecord where
  /-- The error that prompted the repair — kept, not discarded. -/
  error : Err
  /-- What was done. -/
  repair : Repair
  /-- The value after the repair, if there is one. -/
  result : Option Val
  /-- Whether the repaired value validates. -/
  status : PStatus
deriving Repr

/-- Reading a decimal string as an integer. -/
def readIntCell (s : List Char) : Option Int :=
  match parseIntAll s with
  | some n => some n
  | none => parseNatAll s |>.map (fun n => (n : Int))

/-- Reconciling one cell that arrived as text where the schema declares an
integer.  The error travels with the record whatever happens. -/
def reconcileInt (objectId field raw : List Char) : RepairRecord :=
  match readIntCell raw with
  | some n =>
      { error :=
          { id := "err.type".toList ++ field, code := "TYPE_MISMATCH".toList,
            severity := .warning,
            message := "schema declares integer, value arrived as string".toList,
            location := field, field, objectId, sourceSystem := "csv".toList,
            sourceFormat := .csv, expected := "integer".toList, actual := raw,
            cause := "schema declares integer".toList,
            resolution := Repair.stringToInteger.name, recoverable := true }
        repair := .stringToInteger, result := some (.int n), status := .valid }
  | none =>
      { error :=
          { id := "err.type".toList ++ field, code := "TYPE_MISMATCH".toList,
            severity := .error,
            message := "schema declares integer, value arrived as string".toList,
            location := field, field, objectId, sourceSystem := "csv".toList,
            sourceFormat := .csv, expected := "integer".toList, actual := raw,
            cause := "schema declares integer".toList,
            resolution := Repair.unresolved.name, recoverable := false }
        repair := .unresolved, result := none, status := .invalid }

/-- **A repair keeps the error.**  The record still says what was expected,
what arrived, and what was done about it. -/
theorem repair_keeps_the_error (objectId field raw : List Char) :
    (reconcileInt objectId field raw).error.code = "TYPE_MISMATCH".toList ∧
      (reconcileInt objectId field raw).error.expected = "integer".toList ∧
      (reconcileInt objectId field raw).error.actual = raw ∧
      (reconcileInt objectId field raw).error.resolution =
        (reconcileInt objectId field raw).repair.name := by
  unfold reconcileInt
  cases readIntCell raw <;> exact ⟨rfl, rfl, rfl, rfl⟩

/-- **A resolved error revalidates**, and the ledger says with what. -/
theorem resolved_revalidates (objectId field raw : List Char) {n : Int}
    (h : readIntCell raw = some n) :
    (reconcileInt objectId field raw).repair = .stringToInteger ∧
      (reconcileInt objectId field raw).result = some (.int n) ∧
      (reconcileInt objectId field raw).status = .valid := by
  simp [reconcileInt, h]

/-- **An error that cannot be resolved stays visible**, is not marked
recoverable, and does not yield a value. -/
theorem unresolved_stays_visible (objectId field raw : List Char)
    (h : readIntCell raw = none) :
    (reconcileInt objectId field raw).repair = .unresolved ∧
      (reconcileInt objectId field raw).result = none ∧
      (reconcileInt objectId field raw).status = .invalid ∧
      (reconcileInt objectId field raw).error.recoverable = false := by
  simp [reconcileInt, h]

/-- **A repair never proves anything.**  Coercing a cell revalidates the
*syntax* of a value; it leaves the truth status of the object where it
was, because a repair is not a validation event. -/
theorem repair_is_not_a_proof (d : Domain) (oid : Id) (t : Truth) :
    (step d oid .nothing t).1 = t := rfl

end Kant.Dom
