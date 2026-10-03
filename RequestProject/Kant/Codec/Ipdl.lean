/-
# The IPDL codec

IPDL is treated as a native structured interchange language: it carries
identifiers, types, nesting, **references** and **annotations**, which the
canonical model has no constructor for.  The standard says such constructs
must be represented through an extension field rather than discarded, and
that is exactly what this adapter does: a reference becomes the reserved
object `{"$ipdl.ref": …}` and an annotation the reserved object
`{"$ipdl.annotation": …, "$ipdl.note": …, "$ipdl.body": …}`.

The wire form is the deterministic canonical framing behind an
`ipdl/1.0;` header, so an IPDL document has the same stable content
identity as the canonical object it denotes.

Proved here:

* `project_embed` — `Canonical → IPDL → Canonical` returns the value
  unchanged: the conversion is `LOSSLESS`;
* `recover_project` — `IPDL → Canonical → IPDL` returns the *document*
  unchanged, references and annotations included, for every document
  that leaves the reserved key space alone (`Clean`);
* `ipdlRead_ipdlText` — the wire form round-trips;
* `ipdlText_injective` — distinct clean documents have distinct text.
-/
import Mathlib
import RequestProject.Kant.Codec.Val
import RequestProject.Kant.Codec.Xml

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.Codec

/-! ## The IPDL document -/

/-- An IPDL document: the canonical shapes, plus references and
annotations. -/
inductive Ipdl where
  | null
  | bool (b : Bool)
  | int (n : Int)
  | str (s : List Char)
  | list (xs : List Ipdl)
  | obj (fs : List (List Char × Ipdl))
  | ref (target : List Char)
  | annot (key : List Char) (note : List Char) (body : Ipdl)
deriving Repr, Inhabited

/-- `$ipdl.ref` -/
def ipdlRefKey : List Char := "$ipdl.ref".toList
/-- `$ipdl.annotation` -/
def ipdlAnnotKey : List Char := "$ipdl.annotation".toList
/-- `$ipdl.note` -/
def ipdlNoteKey : List Char := "$ipdl.note".toList
/-- `$ipdl.body` -/
def ipdlBodyKey : List Char := "$ipdl.body".toList

/-- A key the adapter reserves for constructs the canonical model has no
constructor for. -/
def IpdlReserved (k : List Char) : Prop :=
  k = ipdlRefKey ∨ k = ipdlAnnotKey ∨ k = ipdlNoteKey ∨ k = ipdlBodyKey

instance (k : List Char) : Decidable (IpdlReserved k) := by
  unfold IpdlReserved; infer_instance

/-- A document that leaves the reserved key space alone. -/
inductive Ipdl.Clean : Ipdl → Prop
  | null : Ipdl.Clean .null
  | bool (b : Bool) : Ipdl.Clean (.bool b)
  | int (n : Int) : Ipdl.Clean (.int n)
  | str (s : List Char) : Ipdl.Clean (.str s)
  | list (xs : List Ipdl) : (∀ x ∈ xs, Ipdl.Clean x) → Ipdl.Clean (.list xs)
  | obj (fs : List (List Char × Ipdl)) :
      (∀ kv ∈ fs, ¬ IpdlReserved kv.1) → (∀ kv ∈ fs, Ipdl.Clean kv.2) → Ipdl.Clean (.obj fs)
  | ref (t : List Char) : Ipdl.Clean (.ref t)
  | annot (k n : List Char) (b : Ipdl) : Ipdl.Clean b → Ipdl.Clean (.annot k n b)

/-! ## Between IPDL and the canonical model -/

mutual

/-- An IPDL document as a canonical value. -/
def project : Ipdl → Val
  | .null => .null
  | .bool b => .bool b
  | .int n => .int n
  | .str s => .str s
  | .list xs => .list (projectList xs)
  | .obj fs => .obj (projectFields fs)
  | .ref t => .obj [(ipdlRefKey, .str t)]
  | .annot k n b =>
      .obj [(ipdlAnnotKey, .str k), (ipdlNoteKey, .str n), (ipdlBodyKey, project b)]

/-- The elements of an IPDL sequence, projected. -/
def projectList : List Ipdl → List Val
  | [] => []
  | x :: xs => project x :: projectList xs

/-- The fields of an IPDL object, projected. -/
def projectFields : List (List Char × Ipdl) → List (List Char × Val)
  | [] => []
  | (k, v) :: fs => (k, project v) :: projectFields fs

end

/-- Recognising the reserved shapes once the children have been read
back. -/
def rebuild : List (List Char × Ipdl) → Ipdl
  | [(k, .str t)] => if k = ipdlRefKey then .ref t else .obj [(k, .str t)]
  | [(k1, .str k), (k2, .str n), (k3, b)] =>
      if k1 = ipdlAnnotKey ∧ k2 = ipdlNoteKey ∧ k3 = ipdlBodyKey then .annot k n b
      else .obj [(k1, .str k), (k2, .str n), (k3, b)]
  | fs => .obj fs

theorem rebuild_of_clean {fs : List (List Char × Ipdl)}
    (h : ∀ kv ∈ fs, ¬ IpdlReserved kv.1) : rebuild fs = .obj fs := by
  match fs with
  | [] => simp [rebuild]
  | [(k, v)] =>
      cases v with
      | str t =>
          have hk : k ≠ ipdlRefKey := fun hk => h (k, .str t) (by simp) (Or.inl hk)
          simp [rebuild, hk]
      | _ => simp [rebuild]
  | [a, b] => simp [rebuild]
  | [(k1, v1), (k2, v2), (k3, v3)] =>
      cases v1 with
      | str t1 =>
          cases v2 with
          | str t2 =>
              have hk : ¬ (k1 = ipdlAnnotKey ∧ k2 = ipdlNoteKey ∧ k3 = ipdlBodyKey) := by
                rintro ⟨h1, -, -⟩
                exact h (k1, .str t1) (by simp) (Or.inr (Or.inl h1))
              simp [rebuild, hk]
          | _ => simp [rebuild]
      | _ => simp [rebuild]
  | a :: b :: c :: d :: rest => simp [rebuild]

mutual

/-- A canonical value read back as an IPDL document, reserved keys
included. -/
def recover : Val → Option Ipdl
  | .null => some .null
  | .bool b => some (.bool b)
  | .int n => some (.int n)
  | .str s => some (.str s)
  | .list xs => (recoverList xs).map Ipdl.list
  | .obj fs => (recoverFields fs).map rebuild

/-- The elements of a canonical sequence, read back. -/
def recoverList : List Val → Option (List Ipdl)
  | [] => some []
  | x :: xs =>
      match recover x, recoverList xs with
      | some y, some ys => some (y :: ys)
      | _, _ => none

/-- The fields of a canonical object, read back. -/
def recoverFields : List (List Char × Val) → Option (List (List Char × Ipdl))
  | [] => some []
  | (k, v) :: fs =>
      match recover v, recoverFields fs with
      | some y, some ys => some ((k, y) :: ys)
      | _, _ => none

end

mutual

/-- A canonical value as an IPDL document. -/
def embed : Val → Ipdl
  | .null => .null
  | .bool b => .bool b
  | .int n => .int n
  | .str s => .str s
  | .list xs => .list (embedList xs)
  | .obj fs => .obj (embedFields fs)

/-- The elements of a canonical sequence, embedded. -/
def embedList : List Val → List Ipdl
  | [] => []
  | x :: xs => embed x :: embedList xs

/-- The fields of a canonical object, embedded. -/
def embedFields : List (List Char × Val) → List (List Char × Ipdl)
  | [] => []
  | (k, v) :: fs => (k, embed v) :: embedFields fs

end

/-- **`Canonical → IPDL → Canonical` is lossless.** -/
theorem project_embed (v : Val) : project (embed v) = v := by
  induction v using Val.strong with
  | hnull => simp [embed, project]
  | hbool b => simp [embed, project]
  | hint n => simp [embed, project]
  | hstr s => simp [embed, project]
  | hlist xs hxs =>
      have h : projectList (embedList xs) = xs := by
        induction xs with
        | nil => simp [embedList, projectList]
        | cons a as ih =>
            have ha := hxs a (by simp)
            have has := ih (fun v hv => hxs v (by simp [hv]))
            simp [embedList, projectList, ha, has]
      simp [embed, project, h]
  | hobj fs hfs =>
      have h : projectFields (embedFields fs) = fs := by
        induction fs with
        | nil => simp [embedFields, projectFields]
        | cons a as ih =>
            obtain ⟨k, v⟩ := a
            have ha := hfs (k, v) (by simp)
            have has := ih (fun kv hkv => hfs kv (by simp [hkv]))
            simp [embedFields, projectFields, ha, has]
      simp [embed, project, h]

/-- **`IPDL → Canonical → IPDL` keeps everything**, references and
annotations included, as long as the document leaves the reserved keys
alone. -/
theorem recover_project {i : Ipdl} (hi : Ipdl.Clean i) : recover (project i) = some i := by
  induction hi with
  | null => simp [project, recover]
  | bool b => simp [project, recover]
  | int n => simp [project, recover]
  | str s => simp [project, recover]
  | list xs hcl ih =>
      have h : recoverList (projectList xs) = some xs := by
        induction xs with
        | nil => simp [projectList, recoverList]
        | cons a as ihs =>
            have ha := ih a (by simp)
            have has := ihs (fun x hx => hcl x (by simp [hx])) (fun x hx => ih x (by simp [hx]))
            simp [projectList, recoverList, ha, has]
      simp [project, recover, h]
  | obj fs hres hcl ih =>
      have h : recoverFields (projectFields fs) = some fs := by
        induction fs with
        | nil => simp [projectFields, recoverFields]
        | cons a as ihs =>
            obtain ⟨k, v⟩ := a
            have ha := ih (k, v) (by simp)
            have has := ihs (fun kv hkv => hres kv (by simp [hkv]))
              (fun kv hkv => hcl kv (by simp [hkv])) (fun kv hkv => ih kv (by simp [hkv]))
            simp [projectFields, recoverFields, ha, has]
      simp [project, recover, h, rebuild_of_clean hres]
  | ref t => simp [project, recover, recoverFields, rebuild, ipdlRefKey]
  | annot k n b _ ih =>
      simp [project, recover, recoverFields, ih, rebuild, ipdlAnnotKey, ipdlNoteKey, ipdlBodyKey]

/-- Recognising a reserved shape does not change what the document
means: whatever `rebuild` makes of a field list, it projects back to the
object those fields describe. -/
theorem project_rebuild (fs : List (List Char × Ipdl)) :
    project (rebuild fs) = .obj (projectFields fs) := by
  match fs with
  | [] => simp [rebuild, project, projectFields]
  | [(k, v)] =>
      cases v with
      | str t =>
          by_cases hk : k = ipdlRefKey
          · subst hk; simp [rebuild, project, projectFields]
          · simp [rebuild, hk, project, projectFields]
      | _ => simp [rebuild, project, projectFields]
  | [a, b] => simp [rebuild, project, projectFields]
  | [(k1, v1), (k2, v2), (k3, v3)] =>
      cases v1 with
      | str t1 =>
          cases v2 with
          | str t2 =>
              by_cases hk : k1 = ipdlAnnotKey ∧ k2 = ipdlNoteKey ∧ k3 = ipdlBodyKey
              · obtain ⟨h1, h2, h3⟩ := hk
                subst h1; subst h2; subst h3
                simp [rebuild, project, projectFields]
              · simp [rebuild, hk, project, projectFields]
          | _ => simp [rebuild, project, projectFields]
      | _ => simp [rebuild, project, projectFields]
  | a :: b :: c :: d :: rest => simp [rebuild, project, projectFields]

/-- **`Canonical -> IPDL -> Canonical` reads every canonical value.**  Even
a value that happens to use a reserved key comes back meaning the same
thing: the adapter reads it as a reference or an annotation, and that
reference or annotation projects to exactly the value it came from. -/
theorem project_recover (v : Val) : ∃ i : Ipdl, recover v = some i ∧ project i = v := by
  induction v using Val.strong with
  | hnull => exact ⟨.null, by simp [recover], by simp [project]⟩
  | hbool b => exact ⟨.bool b, by simp [recover], by simp [project]⟩
  | hint n => exact ⟨.int n, by simp [recover], by simp [project]⟩
  | hstr s => exact ⟨.str s, by simp [recover], by simp [project]⟩
  | hlist xs hxs =>
      have h : ∃ ys, recoverList xs = some ys ∧ projectList ys = xs := by
        induction xs with
        | nil => exact ⟨[], by simp [recoverList], by simp [projectList]⟩
        | cons a as ih =>
            obtain ⟨b, hb, hpb⟩ := hxs a (by simp)
            obtain ⟨bs, hbs, hpbs⟩ := ih (fun v hv => hxs v (by simp [hv]))
            exact ⟨b :: bs, by simp [recoverList, hb, hbs], by simp [projectList, hpb, hpbs]⟩
      obtain ⟨ys, hys, hpys⟩ := h
      exact ⟨.list ys, by simp [recover, hys], by simp [project, hpys]⟩
  | hobj fs hfs =>
      have h : ∃ gs, recoverFields fs = some gs ∧ projectFields gs = fs := by
        induction fs with
        | nil => exact ⟨[], by simp [recoverFields], by simp [projectFields]⟩
        | cons a as ih =>
            obtain ⟨k, v⟩ := a
            obtain ⟨b, hb, hpb⟩ := hfs (k, v) (by simp)
            obtain ⟨bs, hbs, hpbs⟩ := ih (fun kv hkv => hfs kv (by simp [hkv]))
            exact ⟨(k, b) :: bs, by simp [recoverFields, hb, hbs],
              by simp [projectFields, hpb, hpbs]⟩
      obtain ⟨gs, hgs, hpgs⟩ := h
      exact ⟨rebuild gs, by simp [recover, hgs], by rw [project_rebuild, hpgs]⟩

/-! ## The wire form -/

/-- `ipdl/1.0;` -/
def ipdlHeader : List Char := 'i' :: "pdl/1.0;".toList

/-- An IPDL document as text. -/
def ipdlText (i : Ipdl) : List Char := ipdlHeader ++ canonEnc (project i)

/-- Text read back as an IPDL document. -/
def ipdlRead (s : List Char) : Option Ipdl :=
  match stripPrefix ipdlHeader s with
  | some body => (canonDecode body).bind recover
  | none => none

/-- **The IPDL wire form round-trips.** -/
theorem ipdlRead_ipdlText {i : Ipdl} (hi : Ipdl.Clean i) : ipdlRead (ipdlText i) = some i := by
  simp [ipdlRead, ipdlText, canonDecode_canonEnc, recover_project hi]

/-- **The full canonical-through-IPDL round trip.**  A canonical value
written as an IPDL document and read back is the same value, with no
cleanliness hypothesis: a value that uses the reserved keys is read as
the reference or annotation those keys denote, which means the same. -/
theorem ipdl_roundTrip (v : Val) : (ipdlRead (ipdlText (embed v))).map project = some v := by
  obtain ⟨i, hi, hpi⟩ := project_recover v
  simp [ipdlRead, ipdlText, project_embed, stripPrefix_append, canonDecode_canonEnc, hi, hpi]

/-- Distinct clean documents have distinct text. -/
theorem ipdlText_injective {a b : Ipdl} (ha : Ipdl.Clean a) (hb : Ipdl.Clean b)
    (h : ipdlText a = ipdlText b) : a = b := by
  have h1 := ipdlRead_ipdlText ha
  rw [h, ipdlRead_ipdlText hb] at h1
  exact (Option.some.inj h1).symm

/-- The canonical text of an IPDL document is the canonical text of the
value it denotes, so IPDL and the canonical model share one content
identity. -/
theorem ipdlText_hash (i : Ipdl) : ipdlText i = ipdlHeader ++ canonEnc (project i) := rfl

end Kant.Codec
