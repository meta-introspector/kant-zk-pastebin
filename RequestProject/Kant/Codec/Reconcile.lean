/-
# Reconciliation: comparing two systems, and resolving what they disagree
about

Two systems each decode their own native data into a canonical object.
The comparator then works on the canonical objects, not on the native
formats, and expresses disagreement as structured `Difference`s rather
than as prose.

Proved here:

* `diffVal_nil_iff` — the difference list is empty **exactly** when the
  two values are the same, so a comparison never invents or hides a
  disagreement;
* `compareObj_equivalent_iff` — the verdict is `EQUIVALENT` exactly when
  the two objects are the same object;
* `compareObj_symm` — the comparator does not care which side is which;
* `conflict_valid` — a `CONFLICT` is only ever reported when two systems
  both claim `VALID` and their outputs differ;
* `resolve_reject`, `resolve_records` — **conflicts are never silently
  merged**: rejecting produces nothing, and every resolution that does
  produce an object records itself in that object's provenance.
-/
import Mathlib
import RequestProject.Kant.Codec.Model
import RequestProject.Kant.Codec.Yaml

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.Codec

/-! ## Differences -/

/-- One structured disagreement. -/
structure Difference where
  /-- Where in the object the two sides differ. -/
  path : List Char
  /-- What the left side says. -/
  left : List Char
  /-- What the right side says. -/
  right : List Char
  /-- `VALUE_MISMATCH`, `TYPE_MISMATCH`, `KEY_MISMATCH`, `MISSING_LEFT`,
  `MISSING_RIGHT`. -/
  kind : List Char
  /-- How bad it is. -/
  severity : Severity
  /-- Why the comparator said so. -/
  explanation : List Char
deriving Repr, Inhabited

/-- A difference at a path. -/
def mkDiff (path l r : List Char) (kind : List Char) : Difference :=
  { path := path, left := l, right := r, kind := kind, severity := .error,
    explanation := kind }

mutual

/-- Everything two canonical values disagree about. -/
def diffVal (path : List Char) : Val → Val → List Difference
  | .null, .null => []
  | .bool a, .bool b =>
      if a = b then [] else [mkDiff path (yamlEnc (.bool a)) (yamlEnc (.bool b))
        "VALUE_MISMATCH".toList]
  | .int a, .int b =>
      if a = b then [] else [mkDiff path (yamlEnc (.int a)) (yamlEnc (.int b))
        "VALUE_MISMATCH".toList]
  | .str a, .str b =>
      if a = b then [] else [mkDiff path (yamlEnc (.str a)) (yamlEnc (.str b))
        "VALUE_MISMATCH".toList]
  | .list xs, .list ys => diffList path 0 xs ys
  | .obj fs, .obj gs => diffFields path fs gs
  | a, b => [mkDiff path (yamlEnc a) (yamlEnc b) "TYPE_MISMATCH".toList]

/-- Everything two sequences disagree about. -/
def diffList (path : List Char) (i : Nat) : List Val → List Val → List Difference
  | [], [] => []
  | [], y :: ys =>
      mkDiff (path ++ '[' :: natDigits i) [] (yamlEnc y) "MISSING_LEFT".toList
        :: diffList path (i + 1) [] ys
  | x :: xs, [] =>
      mkDiff (path ++ '[' :: natDigits i) (yamlEnc x) [] "MISSING_RIGHT".toList
        :: diffList path (i + 1) xs []
  | x :: xs, y :: ys =>
      diffVal (path ++ '[' :: natDigits i) x y ++ diffList path (i + 1) xs ys

/-- Everything two mappings disagree about. -/
def diffFields (path : List Char) :
    List (List Char × Val) → List (List Char × Val) → List Difference
  | [], [] => []
  | [], (k, y) :: gs =>
      mkDiff (path ++ '.' :: k) [] (yamlEnc y) "MISSING_LEFT".toList :: diffFields path [] gs
  | (k, x) :: fs, [] =>
      mkDiff (path ++ '.' :: k) (yamlEnc x) [] "MISSING_RIGHT".toList :: diffFields path fs []
  | (k, x) :: fs, (l, y) :: gs =>
      if k = l then diffVal (path ++ '.' :: k) x y ++ diffFields path fs gs
      else mkDiff (path ++ '.' :: k) k l "KEY_MISMATCH".toList :: diffFields path fs gs

end

theorem diffVal_self (path : List Char) (v : Val) : diffVal path v v = [] := by
  induction v using Val.strong generalizing path with
  | hnull => simp [diffVal]
  | hbool b => simp [diffVal]
  | hint n => simp [diffVal]
  | hstr s => simp [diffVal]
  | hlist xs hxs =>
      have h : ∀ i p, diffList p i xs xs = [] := by
        intro i p
        induction xs generalizing i with
        | nil => simp [diffList]
        | cons a as ih =>
            have ha := hxs a (by simp) (p ++ '[' :: natDigits i)
            simp [diffList, ha, ih (fun v hv => hxs v (by simp [hv]))]
      simp [diffVal, h]
  | hobj fs hfs =>
      have h : ∀ p, diffFields p fs fs = [] := by
        intro p
        induction fs with
        | nil => simp [diffFields]
        | cons a as ih =>
            obtain ⟨k, v⟩ := a
            have ha := hfs (k, v) (by simp) (p ++ '.' :: k)
            simp [diffFields, ha, ih (fun kv hkv => hfs kv (by simp [hkv]))]
      simp [diffVal, h]

theorem diffVal_eq_nil_imp (path : List Char) (a b : Val) (h : diffVal path a b = []) : a = b := by
  induction a using Val.strong generalizing path b with
  | hnull => cases b <;> simp_all [diffVal]
  | hbool x => cases b <;> simp_all [diffVal]
  | hint x => cases b <;> simp_all [diffVal]
  | hstr x => cases b <;> simp_all [diffVal]
  | hlist xs hxs =>
      cases b with
      | list ys =>
          have key : ∀ (xs ys : List Val), (∀ v ∈ xs, ∀ (p : List Char) (b : Val),
              diffVal p v b = [] → v = b) → ∀ i p, diffList p i xs ys = [] → xs = ys := by
            intro xs
            induction xs with
            | nil =>
                intro ys _ i p h
                cases ys with
                | nil => rfl
                | cons y ys => simp [diffList] at h
            | cons a as ih =>
                intro ys hxs i p h
                cases ys with
                | nil => simp [diffList] at h
                | cons y ys =>
                    simp only [diffList, List.append_eq_nil_iff] at h
                    obtain ⟨h1, h2⟩ := h
                    have ha := hxs a (by simp) _ y h1
                    have has := ih ys (fun v hv => hxs v (by simp [hv])) (i + 1) p h2
                    rw [ha, has]
          have := key xs ys hxs 0 path (by simpa [diffVal] using h)
          rw [this]
      | _ => simp_all [diffVal]
  | hobj fs hfs =>
      cases b with
      | obj gs =>
          have key : ∀ (fs gs : List (List Char × Val)), (∀ kv ∈ fs, ∀ (p : List Char) (b : Val),
              diffVal p kv.2 b = [] → kv.2 = b) → ∀ p, diffFields p fs gs = [] → fs = gs := by
            intro fs
            induction fs with
            | nil =>
                intro gs _ p h
                cases gs with
                | nil => rfl
                | cons g gs => obtain ⟨k, y⟩ := g; simp [diffFields] at h
            | cons a as ih =>
                intro gs hfs p h
                obtain ⟨k, x⟩ := a
                cases gs with
                | nil => simp [diffFields] at h
                | cons g gs =>
                    obtain ⟨l, y⟩ := g
                    by_cases hkl : k = l
                    · subst hkl
                      rw [diffFields] at h
                      simp only [if_true, List.append_eq_nil_iff] at h
                      obtain ⟨h1, h2⟩ := h
                      have ha : x = y := hfs (k, x) (by simp) _ y h1
                      have has := ih gs (fun kv hkv => hfs kv (by simp [hkv])) p h2
                      rw [ha, has]
                    · rw [diffFields] at h
                      simp [hkl] at h
          have := key fs gs hfs path (by simpa [diffVal] using h)
          rw [this]
      | _ => simp_all [diffVal]

/-- **A comparison never invents or hides a disagreement.** -/
theorem diffVal_nil_iff (path : List Char) (a b : Val) : diffVal path a b = [] ↔ a = b :=
  ⟨diffVal_eq_nil_imp path a b, fun h => h ▸ diffVal_self path a⟩

/-! ## The verdict -/

/-- What a comparison of two canonical objects can say. -/
inductive Verdict
  | equivalent | different | conflict | incomparable | incomplete
deriving DecidableEq, Repr, Inhabited

/-- The name of a verdict. -/
def Verdict.name : Verdict → List Char
  | .equivalent => "EQUIVALENT".toList
  | .different => "DIFFERENT".toList
  | .conflict => "CONFLICT".toList
  | .incomparable => "INCOMPARABLE".toList
  | .incomplete => "INCOMPLETE".toList

/-- A status that says the system has not finished. -/
def Status.unsettled : Status → Bool
  | .unknown => true
  | .pending => true
  | _ => false

/-- The canonical text of an object's outputs. -/
def outputsText (o : Obj) : List Char := canonEnc (.list (o.outputs.map Outp.toVal))

/-- Comparing two canonical objects. -/
def compareObj (a b : Obj) : Verdict :=
  if a.text = b.text then .equivalent
  else if a.kind ≠ b.kind then .incomparable
  else if a.status.unsettled || b.status.unsettled then .incomplete
  else if a.status = .valid ∧ b.status = .valid ∧ outputsText a ≠ outputsText b then .conflict
  else .different

/-- **`EQUIVALENT` means the same object.** -/
theorem compareObj_equivalent_iff (a b : Obj) : compareObj a b = .equivalent ↔ a = b := by
  constructor
  · intro h
    by_cases ht : a.text = b.text
    · exact Obj.eq_of_text_eq ht
    · rw [compareObj, if_neg ht] at h
      split at h
      · exact absurd h (by decide)
      · split at h
        · exact absurd h (by decide)
        · split at h <;> exact absurd h (by decide)
  · intro h
    subst h
    rw [compareObj, if_pos rfl]

/-- The comparator does not care which side is which. -/
theorem compareObj_symm (a b : Obj) : compareObj a b = compareObj b a := by
  have e1 : (a.text = b.text) ↔ (b.text = a.text) := eq_comm
  have e2 : (¬ a.kind = b.kind) ↔ (¬ b.kind = a.kind) := by
    constructor <;> (intro h hx; exact h hx.symm)
  have e3 : (a.status.unsettled || b.status.unsettled)
      = (b.status.unsettled || a.status.unsettled) := Bool.or_comm _ _
  have e4 : (a.status = Status.valid ∧ b.status = Status.valid ∧ outputsText a ≠ outputsText b)
      ↔ (b.status = Status.valid ∧ a.status = Status.valid ∧ outputsText b ≠ outputsText a) := by
    constructor <;> (rintro ⟨x, y, z⟩; exact ⟨y, x, fun h => z h.symm⟩)
  unfold compareObj
  simp only [ne_eq, e1, e2, e3, e4]

/-- **A conflict is only ever reported between two systems that both
claim `VALID` and disagree about the outputs.** -/
theorem conflict_valid {a b : Obj} (h : compareObj a b = .conflict) :
    a.status = .valid ∧ b.status = .valid ∧ outputsText a ≠ outputsText b := by
  rw [compareObj] at h
  split at h
  · exact absurd h (by decide)
  · split at h
    · exact absurd h (by decide)
    · split at h
      · exact absurd h (by decide)
      · split at h
        · assumption
        · exact absurd h (by decide)

/-- And a conflict really is a disagreement about the answers. -/
theorem conflict_outputs_differ {a b : Obj} (h : compareObj a b = .conflict) :
    a.outputs.map Outp.toVal ≠ b.outputs.map Outp.toVal := by
  intro hout
  exact (conflict_valid h).2.2 (by rw [outputsText, outputsText, hout])

/-! ## Resolution -/

/-- How a conflict may be resolved. -/
inductive Strategy
  | preferSource | preferVerified | preferNewer | manual | merge | reject
deriving DecidableEq, Repr, Inhabited

/-- The name of a strategy. -/
def Strategy.name : Strategy → List Char
  | .preferSource => "prefer_source".toList
  | .preferVerified => "prefer_verified".toList
  | .preferNewer => "prefer_newer".toList
  | .manual => "manual_resolution".toList
  | .merge => "merge".toList
  | .reject => "reject".toList

/-- The record a resolution leaves behind. -/
def resolutionRecord (s : Strategy) (a b : Obj) : Trans :=
  { id := "resolution".toList, operation := s.name, source := .canonical, dest := .canonical,
    inputHash := a.hash, outputHash := b.hash, codec := .canonical,
    codecVersion := "proof-schema/1.0".toList, lossiness := .lossy, errors := [], warnings := [] }

/-- Which side a strategy keeps.  `manual` and `reject` keep neither:
nothing is produced without a human, and nothing is merged silently. -/
def resolve (s : Strategy) (a b : Obj) : Option Obj :=
  match s with
  | .preferSource => some a
  | .preferVerified => if b.status = .valid ∧ a.status ≠ .valid then some b else some a
  | .preferNewer => some b
  | .merge => some { a with warnings := a.warnings ++ b.warnings, extensions := a.extensions ++ b.extensions }
  | .manual => none
  | .reject => none

/-- The provenance a resolution leaves on the object it produces. -/
def resolutionProv (s : Strategy) (a b : Obj) (o : Obj) : Prov :=
  { sourceSystem := "reconciler".toList, sourceFile := [], sourceFormat := .canonical,
    importedAt := 0, transformedAt := 0,
    transformations :=
      (match o.provenance with
       | some p => p.transformations
       | none => []) ++ [resolutionRecord s a b],
    parent := a.hash }

/-- The resolved object, with the resolution recorded in its provenance. -/
def resolved (s : Strategy) (a b : Obj) : Option Obj :=
  (resolve s a b).map (fun o => { o with provenance := some (resolutionProv s a b o) })

/-- **Rejecting produces nothing.** -/
theorem resolve_reject (a b : Obj) : resolved .reject a b = none := by
  simp [resolved, resolve]

/-- And neither does asking for a human. -/
theorem resolve_manual (a b : Obj) : resolved .manual a b = none := by
  simp [resolved, resolve]

/-- **Every resolution that produces an object records itself.** -/
theorem resolve_records {s : Strategy} {a b o : Obj} (h : resolved s a b = some o) :
    ∃ p, o.provenance = some p ∧ resolutionRecord s a b ∈ p.transformations := by
  unfold resolved at h
  cases hr : resolve s a b with
  | none => rw [hr] at h; simp at h
  | some x =>
      rw [hr] at h
      simp only [Option.map_some, Option.some.injEq] at h
      subst h
      exact ⟨resolutionProv s a b x, rfl, by simp [resolutionProv]⟩

/-- A merge has to be asked for by name, and it keeps both sides'
warnings and extensions. -/
theorem merge_keeps_both {a b o : Obj} (h : resolved .merge a b = some o) :
    o.warnings = a.warnings ++ b.warnings ∧ o.extensions = a.extensions ++ b.extensions := by
  simp only [resolved, resolve, Option.map_some, Option.some.injEq] at h
  subst h
  exact ⟨rfl, rfl⟩

/-- A merge does produce an object; the other strategies that produce
none do so by design. -/
theorem merge_produces (a b : Obj) : (resolved .merge a b).isSome := by
  simp [resolved, resolve]

end Kant.Codec
