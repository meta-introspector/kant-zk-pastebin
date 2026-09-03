/-
# The CSV codec

CSV is a *tabular projection* of the canonical model, not a second
canonical model.  The convention is the one the standard recommends —

```text
object_id,object_type,field,value,value_type,parent_id
```

— with one addition that the standard also demands: a codec must document
what its target cannot represent directly.  A flat table cannot express
nesting, so a container row carries the number of its children in the
`value` column, with `value_type` set to `count`, and the children follow
it in document order.  With that convention the projection is complete.

Proved here:

* `csvDecode_csvEncode` — **the tabular projection round-trips** for
  every canonical value;
* `csvEncode_injective` — so, with the counts, the conversion is not
  lossy;
* `flatRows_lossy` — and without them it is: two different values have
  exactly the same scalar-only table, which is why the bare
  `object_id,…,value` convention is `PARTIAL` rather than `LOSSLESS`.
-/
import Mathlib
import RequestProject.Kant.Codec.Val
import RequestProject.Kant.Codec.Yaml
import RequestProject.Kant.Codec.Xml

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.Codec

/-! ## Rows -/

/-- One row of the tabular projection. -/
structure Row where
  /-- The identity of the object this row describes. -/
  objectId : List Char
  /-- `value`, `list` or `object`. -/
  objectType : List Char
  /-- The key (for a mapping entry) or index (for a sequence element). -/
  field : List Char
  /-- The scalar, or the number of children. -/
  value : List Char
  /-- `null`, `bool`, `integer`, `string` or `count`. -/
  valueType : List Char
  /-- The identity of the parent, empty at the root. -/
  parentId : List Char
deriving DecidableEq, Repr, Inhabited

/-- Reading a whole field as a natural number. -/
def parseNatAll (s : List Char) : Option Nat :=
  match readDigits 0 s with
  | (n, []) => some n
  | _ => none

theorem parseNatAll_natDigits (n : Nat) : parseNatAll (natDigits n) = some n := by
  have h := readDigits_natDigits n [] (by simp [NotDigit])
  simp only [List.append_nil] at h
  simp [parseNatAll, h]

/-- Reading a whole field as an integer. -/
def parseIntAll (s : List Char) : Option Int :=
  match readNumY s with
  | some (n, []) => some n
  | _ => none

theorem parseIntAll_encNumY (n : Int) : parseIntAll (encNumY n) = some n := by
  have h := readNumY_encNumY n [] (by simp [NotDigit])
  simp only [List.append_nil] at h
  simp [parseIntAll, h]

/-! ## The projection -/

mutual

/-- The rows of one value. -/
def rowsVal (id parent field : List Char) : Val → List Row
  | .null => [⟨id, "value".toList, field, [], "null".toList, parent⟩]
  | .bool b =>
      [⟨id, "value".toList, field, (if b then "true".toList else "false".toList),
        "bool".toList, parent⟩]
  | .int n => [⟨id, "value".toList, field, encNumY n, "integer".toList, parent⟩]
  | .str s => [⟨id, "value".toList, field, s, "string".toList, parent⟩]
  | .list xs =>
      ⟨id, "list".toList, field, natDigits xs.length, "count".toList, parent⟩ :: rowsList id 0 xs
  | .obj fs =>
      ⟨id, "object".toList, field, natDigits fs.length, "count".toList, parent⟩ ::
        rowsFields id 0 fs

/-- The rows of the elements of a sequence. -/
def rowsList (parent : List Char) (i : Nat) : List Val → List Row
  | [] => []
  | v :: vs =>
      rowsVal (parent ++ '/' :: natDigits i) parent (natDigits i) v ++ rowsList parent (i + 1) vs

/-- The rows of the entries of a mapping. -/
def rowsFields (parent : List Char) (i : Nat) : List (List Char × Val) → List Row
  | [] => []
  | (k, v) :: fs =>
      rowsVal (parent ++ '/' :: natDigits i) parent k v ++ rowsFields parent (i + 1) fs

end

mutual

/-- Reading one value off the front of a table. -/
def readRowVal : Nat → List Row → Option (Val × List Row)
  | 0, _ => none
  | _ + 1, [] => none
  | fuel + 1, r :: rs =>
      if r.valueType = "null".toList then some (.null, rs)
      else if r.valueType = "bool".toList then some (.bool (r.value = "true".toList), rs)
      else if r.valueType = "integer".toList then (parseIntAll r.value).map (fun n => (.int n, rs))
      else if r.valueType = "string".toList then some (.str r.value, rs)
      else if r.valueType = "count".toList then
        match parseNatAll r.value with
        | some n =>
            if r.objectType = "list".toList then
              (readRowList fuel n rs).map (fun p => (Val.list p.1, p.2))
            else if r.objectType = "object".toList then
              (readRowFields fuel n rs).map (fun p => (Val.obj p.1, p.2))
            else none
        | none => none
      else none
  termination_by fuel _ => (fuel, 0)

/-- Reading exactly `n` values. -/
def readRowList : Nat → Nat → List Row → Option (List Val × List Row)
  | _, 0, rs => some ([], rs)
  | fuel, n + 1, rs =>
      match readRowVal fuel rs with
      | some (v, rs') => (readRowList fuel n rs').map (fun p => (v :: p.1, p.2))
      | none => none
  termination_by fuel n _ => (fuel, n + 1)

/-- Reading exactly `n` entries, taking each key from its row. -/
def readRowFields : Nat → Nat → List Row → Option (List (List Char × Val) × List Row)
  | _, 0, rs => some ([], rs)
  | _, _ + 1, [] => none
  | fuel, n + 1, r :: rs =>
      match readRowVal fuel (r :: rs) with
      | some (v, rs') => (readRowFields fuel n rs').map (fun p => ((r.field, v) :: p.1, p.2))
      | none => none
  termination_by fuel n _ => (fuel, n + 1)

end

/-- The round-trip property of one value under the tabular projection. -/
def RowRoundTrips (v : Val) : Prop :=
  ∀ fuel id parent field rest, (rowsVal id parent field v).length ≤ fuel →
    readRowVal fuel (rowsVal id parent field v ++ rest) = some (v, rest)

theorem rowsList_length_cons (parent : List Char) (i : Nat) (v : Val) (vs : List Val) :
    (rowsList parent i (v :: vs)).length
      = (rowsVal (parent ++ '/' :: natDigits i) parent (natDigits i) v).length
        + (rowsList parent (i + 1) vs).length := by
  simp [rowsList]

theorem readRowList_roundTrip (xs : List Val) (h : ∀ v ∈ xs, RowRoundTrips v) :
    ∀ fuel parent i rest, (rowsList parent i xs).length ≤ fuel →
      readRowList fuel xs.length (rowsList parent i xs ++ rest) = some (xs, rest) := by
  induction xs with
  | nil => intro fuel parent i rest _; simp [rowsList, readRowList]
  | cons a as ih =>
      intro fuel parent i rest hlen
      have hcat : rowsList parent i (a :: as) ++ rest
          = rowsVal (parent ++ '/' :: natDigits i) parent (natDigits i) a
            ++ (rowsList parent (i + 1) as ++ rest) := by
        simp [rowsList]
      have hlen' := rowsList_length_cons parent i a as
      have hhead := h a (by simp) fuel (parent ++ '/' :: natDigits i) parent (natDigits i)
        (rowsList parent (i + 1) as ++ rest) (by omega)
      have htail := ih (fun v hv => h v (by simp [hv])) fuel parent (i + 1) rest (by omega)
      rw [hcat]
      simp [readRowList, hhead, htail]

theorem rowsFields_length_cons (parent : List Char) (i : Nat) (k : List Char) (v : Val)
    (fs : List (List Char × Val)) :
    (rowsFields parent i ((k, v) :: fs)).length
      = (rowsVal (parent ++ '/' :: natDigits i) parent k v).length
        + (rowsFields parent (i + 1) fs).length := by
  simp [rowsFields]

theorem rowsVal_ne_nil (id parent field : List Char) (v : Val) :
    ∃ r rs, rowsVal id parent field v = r :: rs := by
  cases v with
  | null => exact ⟨_, _, rfl⟩
  | bool b => exact ⟨_, _, rfl⟩
  | int n => exact ⟨_, _, rfl⟩
  | str s => exact ⟨_, _, rfl⟩
  | list xs => exact ⟨_, _, rfl⟩
  | obj fs => exact ⟨_, _, rfl⟩

theorem rowsVal_head_field (id parent field : List Char) (v : Val) {r : Row} {rs : List Row}
    (h : rowsVal id parent field v = r :: rs) : r.field = field := by
  cases v <;> (rw [rowsVal] at h; injection h with h1 _; subst h1; rfl)

theorem readRowFields_roundTrip (fs : List (List Char × Val)) (h : ∀ kv ∈ fs, RowRoundTrips kv.2) :
    ∀ fuel parent i rest, (rowsFields parent i fs).length ≤ fuel →
      readRowFields fuel fs.length (rowsFields parent i fs ++ rest) = some (fs, rest) := by
  induction fs with
  | nil => intro fuel parent i rest _; simp [rowsFields, readRowFields]
  | cons a as ih =>
      intro fuel parent i rest hlen
      obtain ⟨k, v⟩ := a
      have hlen' := rowsFields_length_cons parent i k v as
      obtain ⟨r0, rs0, hr0⟩ := rowsVal_ne_nil (parent ++ '/' :: natDigits i) parent k v
      have hfield : r0.field = k := rowsVal_head_field _ _ _ v hr0
      have hcat : rowsFields parent i ((k, v) :: as) ++ rest
          = r0 :: (rs0 ++ (rowsFields parent (i + 1) as ++ rest)) := by
        simp [rowsFields, hr0]
      have hhead : readRowVal fuel (rowsVal (parent ++ '/' :: natDigits i) parent k v
          ++ (rowsFields parent (i + 1) as ++ rest))
          = some (v, rowsFields parent (i + 1) as ++ rest) :=
        h (k, v) (by simp) fuel (parent ++ '/' :: natDigits i) parent k _
          (show (rowsVal (parent ++ '/' :: natDigits i) parent k v).length ≤ fuel from by omega)
      have htail := ih (fun kv hkv => h kv (by simp [hkv])) fuel parent (i + 1) rest (by omega)
      rw [hr0] at hhead
      simp only [List.cons_append] at hhead
      cases fuel with
      | zero =>
          have : 0 < (rowsVal (parent ++ '/' :: natDigits i) parent k v).length := by
            rw [hr0]; simp
          omega
      | succ f =>
          rw [hcat]
          simp only [List.length_cons]
          rw [readRowFields.eq_def]
          simp only [hhead, htail, Option.map_some, hfield]

theorem readRowVal_rowsVal (v : Val) : RowRoundTrips v := by
  induction v using Val.strong with
  | hnull =>
      intro fuel id parent field rest hlen
      cases fuel with
      | zero => simp [rowsVal] at hlen
      | succ f => simp +decide [rowsVal, readRowVal]
  | hbool b =>
      intro fuel id parent field rest hlen
      cases fuel with
      | zero => simp [rowsVal] at hlen
      | succ f => cases b <;> simp +decide [rowsVal, readRowVal]
  | hint n =>
      intro fuel id parent field rest hlen
      cases fuel with
      | zero => simp [rowsVal] at hlen
      | succ f => simp +decide [rowsVal, readRowVal, parseIntAll_encNumY]
  | hstr s =>
      intro fuel id parent field rest hlen
      cases fuel with
      | zero => simp [rowsVal] at hlen
      | succ f => simp +decide [rowsVal, readRowVal]
  | hlist xs hxs =>
      intro fuel id parent field rest hlen
      cases fuel with
      | zero => simp [rowsVal] at hlen
      | succ f =>
          have hlen' : (rowsList id 0 xs).length ≤ f := by
            simp [rowsVal] at hlen; omega
          have hbody := readRowList_roundTrip xs hxs f id 0 rest (by omega)
          simp only [rowsVal, List.cons_append]
          rw [readRowVal]
          simp +decide [parseNatAll_natDigits, hbody]
  | hobj fs hfs =>
      intro fuel id parent field rest hlen
      cases fuel with
      | zero => simp [rowsVal] at hlen
      | succ f =>
          have hlen' : (rowsFields id 0 fs).length ≤ f := by
            simp [rowsVal] at hlen; omega
          have hbody := readRowFields_roundTrip fs hfs f id 0 rest (by omega)
          simp only [rowsVal, List.cons_append]
          rw [readRowVal]
          simp +decide [parseNatAll_natDigits, hbody]

/-! ## Rows as text -/

/-- One field, quoted the way CSV quotes. -/
def csvField (s : List Char) : List Char :=
  '"' :: (s.flatMap (fun c => if c = '"' then ['"', '"'] else [c]) ++ ['"'])

/-- Reading a quoted field, after the opening quote. -/
def readCsvField : List Char → Option (List Char × List Char)
  | [] => none
  | '"' :: '"' :: rest => (readCsvField rest).map (fun p => ('"' :: p.1, p.2))
  | '"' :: rest => some ([], rest)
  | c :: rest => (readCsvField rest).map (fun p => (c :: p.1, p.2))

/-- Text that cannot continue a quoted field. -/
def NotQuote (rest : List Char) : Prop := ∀ c ∈ rest.head?, c ≠ '"'

theorem readCsvField_csvField (s rest : List Char) (hr : NotQuote rest) :
    readCsvField (s.flatMap (fun c => if c = '"' then ['"', '"'] else [c]) ++ '"' :: rest)
      = some (s, rest) := by
  induction s with
  | nil =>
      cases rest with
      | nil => simp [readCsvField]
      | cons c cs =>
          have hc : c ≠ '"' := hr c (by simp)
          simp only [List.flatMap_nil, List.nil_append]
          rw [readCsvField.eq_def]
          simp [hc]
  | cons c cs ih =>
      by_cases hq : c = '"'
      · subst hq
        simp only [List.flatMap_cons]
        rw [readCsvField.eq_def]
        simp [ih]
      · simp only [List.flatMap_cons, if_neg hq, List.cons_append, List.nil_append]
        rw [readCsvField.eq_def]
        simp [hq, ih]

/-- One row as a line of CSV. -/
def rowText (r : Row) : List Char :=
  csvField r.objectId ++ (',' :: (csvField r.objectType ++ (',' :: (csvField r.field ++
    (',' :: (csvField r.value ++ (',' :: (csvField r.valueType ++
      (',' :: (csvField r.parentId ++ ['\n']))))))))))

/-- Reading a field and the separator after it. -/
def readCsvCell (sep : Char) : List Char → Option (List Char × List Char)
  | '"' :: s =>
      match readCsvField s with
      | some (v, c :: r) => if c = sep then some (v, r) else none
      | _ => none
  | _ => none

theorem readCsvCell_csvField (sep : Char) (hsep : sep ≠ '"') (s rest : List Char) :
    readCsvCell sep (csvField s ++ sep :: rest) = some (s, rest) := by
  have h := readCsvField_csvField s (sep :: rest) (by simp [NotQuote, hsep])
  simp only [csvField, List.cons_append, List.append_assoc]
  rw [readCsvCell]
  simp [h]

/-- Reading one row. -/
def readRow (s : List Char) : Option (Row × List Char) :=
  match readCsvCell ',' s with
  | some (a, s1) =>
    match readCsvCell ',' s1 with
    | some (b, s2) =>
      match readCsvCell ',' s2 with
      | some (c, s3) =>
        match readCsvCell ',' s3 with
        | some (d, s4) =>
          match readCsvCell ',' s4 with
          | some (e, s5) =>
            match readCsvCell '\n' s5 with
            | some (f, s6) => some (⟨a, b, c, d, e, f⟩, s6)
            | none => none
          | none => none
        | none => none
      | none => none
    | none => none
  | none => none

theorem readRow_rowText (r : Row) (rest : List Char) :
    readRow (rowText r ++ rest) = some (r, rest) := by
  have hc : (',' : Char) ≠ '"' := by decide
  have hn : ('\n' : Char) ≠ '"' := by decide
  obtain ⟨a, b, c, d, e, f⟩ := r
  have hcat : rowText ⟨a, b, c, d, e, f⟩ ++ rest
      = csvField a ++ ',' :: (csvField b ++ ',' :: (csvField c ++ ',' :: (csvField d ++
          ',' :: (csvField e ++ ',' :: (csvField f ++ '\n' :: rest))))) := by
    simp [rowText]
  rw [hcat, readRow]
  simp only [readCsvCell_csvField ',' hc, readCsvCell_csvField '\n' hn]

/-- The whole table as text. -/
def rowsText : List Row → List Char
  | [] => []
  | r :: rs => rowText r ++ rowsText rs

/-- Reading a whole table. -/
def readRows : Nat → List Char → Option (List Row)
  | 0, _ => none
  | _ + 1, [] => some []
  | fuel + 1, s =>
      match readRow s with
      | some (r, s') => (readRows fuel s').map (fun rs => r :: rs)
      | none => none

theorem rowText_ne_nil (r : Row) : rowText r ≠ [] := by
  simp [rowText, csvField]

theorem readRows_rowsText (rs : List Row) :
    ∀ fuel, rs.length < fuel → readRows fuel (rowsText rs) = some rs := by
  induction rs with
  | nil =>
      intro fuel hf
      cases fuel with
      | zero => simp at hf
      | succ f => simp [rowsText, readRows]
  | cons a as ih =>
      intro fuel hf
      cases fuel with
      | zero => simp at hf
      | succ f =>
          have htail := ih f (by simp at hf; omega)
          obtain ⟨c, t, hct⟩ : ∃ c t, rowText a = c :: t := by
            cases h : rowText a with
            | nil => exact absurd h (rowText_ne_nil a)
            | cons c t => exact ⟨c, t, rfl⟩
          have hhead := readRow_rowText a (rowsText as)
          have hcat : rowsText (a :: as) = c :: (t ++ rowsText as) := by
            simp [rowsText, hct]
          rw [hcat, readRows]
          rw [← List.cons_append, ← hct, hhead]
          · simp [htail]
          · simp

/-! ## The codec -/

/-- The header line the convention prescribes. -/
def csvHeader : List Char :=
  'o' :: "bject_id,object_type,field,value,value_type,parent_id\n".toList

/-- A canonical value as a CSV table. -/
def csvEncode (v : Val) : List Char := csvHeader ++ rowsText (rowsVal ['r'] [] [] v)

/-- A CSV table read back as a canonical value. -/
def csvDecode (s : List Char) : Option Val :=
  match stripPrefix csvHeader s with
  | some body =>
      match readRows (body.length + 1) body with
      | some rows =>
          match readRowVal rows.length rows with
          | some (v, []) => some v
          | _ => none
      | none => none
  | none => none

/-- A table has no more rows than its text has characters. -/
theorem rows_length_le (rs : List Row) : rs.length ≤ (rowsText rs).length := by
  induction rs with
  | nil => simp [rowsText]
  | cons a as ih =>
      have hne : 0 < (rowText a).length := by
        cases h : rowText a with
        | nil => exact absurd h (rowText_ne_nil a)
        | cons c t => simp
      simp only [rowsText, List.length_append, List.length_cons]
      omega

/-- **The tabular projection round-trips.** -/
theorem csvDecode_csvEncode (v : Val) : csvDecode (csvEncode v) = some v := by
  have hrt : readRows ((rowsText (rowsVal ['r'] [] [] v)).length + 1)
      (rowsText (rowsVal ['r'] [] [] v)) = some (rowsVal ['r'] [] [] v) :=
    readRows_rowsText _ _ (by have := rows_length_le (rowsVal ['r'] [] [] v); omega)
  have hval : readRowVal (rowsVal ['r'] [] [] v).length ((rowsVal ['r'] [] [] v) ++ [])
      = some (v, []) :=
    readRowVal_rowsVal v (rowsVal ['r'] [] [] v).length ['r'] [] [] [] (le_refl _)
  simp only [List.append_nil] at hval
  simp [csvEncode, csvDecode, hrt, hval]

/-- **The tabular projection is injective**: with the child counts, the
table determines the value. -/
theorem csvEncode_injective {a b : Val} (h : csvEncode a = csvEncode b) : a = b := by
  have ha := csvDecode_csvEncode a
  rw [h, csvDecode_csvEncode b] at ha
  exact (Option.some.inj ha).symm

/-- The scalar-only table: what a CSV export looks like when the
container rows are dropped. -/
def flatRows (v : Val) : List Row := (rowsVal ['r'] [] [] v).filter
  (fun r => r.valueType ≠ "count".toList)

/-- **Without the counts the table is lossy**: an empty sequence and an
empty mapping — and, more damagingly, any two values with the same leaves
— have exactly the same scalar-only table.  This is why a codec must not
claim losslessness for the bare tabular convention. -/
theorem flatRows_lossy : ∃ a b : Val, a ≠ b ∧ flatRows a = flatRows b := by
  refine ⟨.list [], .obj [], ?_, ?_⟩
  · intro h; exact absurd h (by simp)
  · decide

end Kant.Codec
