/-
# The YAML codec

YAML is the human-readable projection of the canonical model.  This
adapter writes the *flow* profile — the subset of YAML in which a
mapping is `{key: value, …}` and a sequence is `[value, …]`, every
string is double-quoted and every escape is explicit — so that the text
is both readable and unambiguously parseable.

Proved here:

* `readQuoted_esc` — quoting and escaping round-trips on its own, for
  every string, whatever characters it contains;
* `yamlDecode_yamlEnc` — **YAML round-trips**: every canonical value
  comes back exactly as it went in;
* `yamlEnc_injective` — the projection is injective, so the conversion
  `Canonical → YAML → Canonical` is `LOSSLESS`.
-/
import Mathlib
import RequestProject.Kant.Codec.Val

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.Codec

/-! ## Quoted strings -/

/-- One character, escaped for a double-quoted YAML scalar. -/
def escChar (c : Char) : List Char :=
  if c = '\\' then ['\\', '\\']
  else if c = '"' then ['\\', '"']
  else if c = '\n' then ['\\', 'n']
  else if c = '\r' then ['\\', 'r']
  else if c = '\t' then ['\\', 't']
  else [c]

/-- A string, escaped for a double-quoted YAML scalar. -/
def esc (s : List Char) : List Char := s.flatMap escChar

/-- The character an escape stands for. -/
def unescChar (c : Char) : Option Char :=
  if c = '\\' then some '\\'
  else if c = '"' then some '"'
  else if c = 'n' then some '\n'
  else if c = 'r' then some '\r'
  else if c = 't' then some '\t'
  else none

/-- Reading the body of a double-quoted scalar, up to the closing quote. -/
def readQuoted : List Char → Option (List Char × List Char)
  | [] => none
  | c :: rest =>
      if c = '"' then some ([], rest)
      else if c = '\\' then
        match rest with
        | [] => none
        | d :: rest' =>
            match unescChar d with
            | some e => (readQuoted rest').map (fun p => (e :: p.1, p.2))
            | none => none
      else (readQuoted rest).map (fun p => (c :: p.1, p.2))
  termination_by s => s.length

/-- **Quoting round-trips**, for every string. -/
theorem readQuoted_esc (s rest : List Char) :
    readQuoted (esc s ++ '"' :: rest) = some (s, rest) := by
  induction s with
  | nil => simp [esc, readQuoted.eq_def]
  | cons c cs ih =>
      have hcat : esc (c :: cs) ++ '"' :: rest = escChar c ++ (esc cs ++ '"' :: rest) := by
        simp [esc, List.flatMap_cons]
      rw [hcat]
      by_cases h1 : c = '\\'
      · subst h1
        simp only [escChar]
        rw [readQuoted.eq_def]
        simp [unescChar, ih]
      · by_cases h2 : c = '"'
        · subst h2
          simp only [escChar, if_neg h1]
          rw [readQuoted.eq_def]
          simp [unescChar, ih]
        · by_cases h3 : c = '\n'
          · subst h3
            simp only [escChar, if_neg h1, if_neg h2]
            rw [readQuoted.eq_def]
            simp [unescChar, ih]
          · by_cases h4 : c = '\r'
            · subst h4
              simp only [escChar, if_neg h1, if_neg h2, if_neg h3]
              rw [readQuoted.eq_def]
              simp [unescChar, ih]
            · by_cases h5 : c = '\t'
              · subst h5
                simp only [escChar, if_neg h1, if_neg h2, if_neg h3, if_neg h4]
                rw [readQuoted.eq_def]
                simp [unescChar, ih]
              · have hcc : escChar c = [c] := by
                  simp [escChar, h1, h2, h3, h4, h5]
                rw [hcc]
                simp only [List.cons_append, List.nil_append]
                rw [readQuoted.eq_def]
                simp [h1, h2, ih]

/-! ## Numbers in plain decimal -/

/-- A number, written the way YAML writes one. -/
def encNumY (n : Int) : List Char :=
  if n < 0 then '-' :: natDigits n.natAbs else natDigits n.natAbs

/-- Reading a maximal run of digits. -/
def readDigits (acc : Nat) : List Char → (Nat × List Char)
  | [] => (acc, [])
  | c :: cs =>
      match digitVal c with
      | some d => readDigits (acc * 10 + d) cs
      | none => (acc, c :: cs)

/-- Text that cannot continue a number. -/
def NotDigit (rest : List Char) : Prop := ∀ c ∈ rest.head?, digitVal c = none

theorem readDigits_append (acc : Nat) (ds rest : List Char)
    (hd : ∀ c ∈ ds, digitVal c ≠ none) (hr : NotDigit rest) :
    readDigits acc (ds ++ rest) = (digitsFold acc ds, rest) := by
  induction ds generalizing acc with
  | nil =>
      cases rest with
      | nil => simp [readDigits, digitsFold]
      | cons c cs =>
          have hc : digitVal c = none := hr c (by simp)
          simp [readDigits, digitsFold, hc]
  | cons c cs ih =>
      have hc : digitVal c ≠ none := hd c (by simp)
      obtain ⟨d, hdv⟩ := Option.ne_none_iff_exists'.1 hc
      simp only [List.cons_append, readDigits, hdv, digitsFold, Option.getD_some]
      exact ih _ (fun x hx => hd x (List.mem_cons_of_mem _ hx))

theorem readDigits_natDigits (n : Nat) (rest : List Char) (hr : NotDigit rest) :
    readDigits 0 (natDigits n ++ rest) = (n, rest) := by
  rw [readDigits_append 0 _ _ (fun c hc => (natDigits_digits n c hc).1) hr, digitsFold_natDigits]
  simp

/-- Reading a number. -/
def readNumY : List Char → Option (Int × List Char)
  | [] => none
  | c :: cs =>
      if c = '-' then
        match cs with
        | [] => none
        | d :: ds =>
            if (digitVal d).isSome then
              let p := readDigits 0 (d :: ds)
              some (-(p.1 : Int), p.2)
            else none
      else if (digitVal c).isSome then
        let p := readDigits 0 (c :: cs)
        some ((p.1 : Int), p.2)
      else none

theorem natDigits_head (n : Nat) : ∃ c cs, natDigits n = c :: cs ∧ digitVal c ≠ none := by
  cases h : natDigits n with
  | nil => exact absurd (h ▸ natDigits_length_pos n) (by simp)
  | cons c cs => exact ⟨c, cs, rfl, (natDigits_digits n c (by rw [h]; simp)).1⟩

theorem readNumY_encNumY (n : Int) (rest : List Char) (hr : NotDigit rest) :
    readNumY (encNumY n ++ rest) = some (n, rest) := by
  obtain ⟨c, cs, hcs, hc⟩ := natDigits_head n.natAbs
  have hcd : (digitVal c).isSome := Option.isSome_iff_ne_none.2 hc
  have hrd : readDigits 0 (c :: (cs ++ rest)) = (n.natAbs, rest) := by
    have := readDigits_natDigits n.natAbs rest hr
    rw [hcs] at this
    simpa using this
  by_cases h : n < 0
  · have habs : -((n.natAbs : Int)) = n := by omega
    have hcat : encNumY n ++ rest = '-' :: (c :: (cs ++ rest)) := by
      simp [encNumY, h, hcs]
    rw [hcat, readNumY.eq_def]
    simp only [hcd, if_pos, hrd, habs]
  · have habs : ((n.natAbs : Int)) = n := by omega
    have hcm : c ≠ '-' := by
      intro hce
      rw [hce] at hc
      exact hc (by decide)
    have hcat : encNumY n ++ rest = c :: (cs ++ rest) := by
      simp [encNumY, h, hcs]
    rw [hcat, readNumY.eq_def]
    simp only [if_neg hcm, hcd, if_pos, hrd, habs]

/-! ## The flow projection -/

mutual

/-- A canonical value as flow-style YAML. -/
def yamlEnc : Val → List Char
  | .null => ['n', 'u', 'l', 'l']
  | .bool true => ['t', 'r', 'u', 'e']
  | .bool false => ['f', 'a', 'l', 's', 'e']
  | .int n => encNumY n
  | .str s => '"' :: (esc s ++ ['"'])
  | .list xs => '[' :: (yamlEncList xs ++ [']'])
  | .obj fs => '{' :: (yamlEncFields fs ++ ['}'])

/-- The elements of a sequence, comma-separated. -/
def yamlEncList : List Val → List Char
  | [] => []
  | [v] => yamlEnc v
  | v :: vs => yamlEnc v ++ ',' :: ' ' :: yamlEncList vs

/-- The entries of a mapping, comma-separated. -/
def yamlEncFields : List (List Char × Val) → List Char
  | [] => []
  | [(k, v)] => '"' :: (esc k ++ '"' :: ':' :: ' ' :: yamlEnc v)
  | (k, v) :: fs =>
      ('"' :: (esc k ++ '"' :: ':' :: ' ' :: yamlEnc v)) ++ ',' :: ' ' :: yamlEncFields fs

end

mutual

/-- The flow-YAML parser. -/
def yVal : Nat → List Char → Option (Val × List Char)
  | 0, _ => none
  | fuel + 1, s =>
      match s with
      | [] => none
      | c :: rest =>
          if c = '"' then (readQuoted rest).map (fun p => (Val.str p.1, p.2))
          else if c = '[' then
            match yList fuel rest with
            | some (xs, r) => some (Val.list xs, r)
            | none => none
          else if c = '{' then
            match yFields fuel rest with
            | some (fs, r) => some (Val.obj fs, r)
            | none => none
          else if c = 'n' then
            match rest with
            | 'u' :: 'l' :: 'l' :: r => some (Val.null, r)
            | _ => none
          else if c = 't' then
            match rest with
            | 'r' :: 'u' :: 'e' :: r => some (Val.bool true, r)
            | _ => none
          else if c = 'f' then
            match rest with
            | 'a' :: 'l' :: 's' :: 'e' :: r => some (Val.bool false, r)
            | _ => none
          else (readNumY (c :: rest)).map (fun p => (Val.int p.1, p.2))
  termination_by fuel _ => (fuel, 1)

/-- The rest of a sequence: values up to the closing bracket. -/
def yList : Nat → List Char → Option (List Val × List Char)
  | 0, _ => none
  | fuel + 1, s =>
      match s with
      | [] => none
      | c :: r0 =>
          if c = ']' then some ([], r0)
          else
            match yVal fuel (c :: r0) with
            | some (v, r) =>
                match r with
                | ']' :: r' => some ([v], r')
                | ',' :: ' ' :: r' =>
                    match yList fuel r' with
                    | some (vs, r'') => some (v :: vs, r'')
                    | none => none
                | _ => none
            | none => none
  termination_by fuel _ => (fuel, 0)

/-- The rest of a mapping: entries up to the closing brace. -/
def yFields : Nat → List Char → Option (List (List Char × Val) × List Char)
  | 0, _ => none
  | fuel + 1, s =>
      match s with
      | [] => none
      | c :: s0 =>
          if c = '}' then some ([], s0)
          else if c = '"' then
            match readQuoted s0 with
            | some (k, ':' :: ' ' :: s1) =>
                match yVal fuel s1 with
                | some (v, r) =>
                    match r with
                    | '}' :: r' => some ([(k, v)], r')
                    | ',' :: ' ' :: r' =>
                        match yFields fuel r' with
                        | some (fs, r'') => some ((k, v) :: fs, r'')
                        | none => none
                    | _ => none
                | none => none
            | _ => none
          else none
  termination_by fuel _ => (fuel, 0)

end

/-! ## The round trip -/

theorem yamlEncList_length_single (a : Val) : (yamlEncList [a]).length = (yamlEnc a).length := rfl

theorem yamlEncList_length_cons (a b : Val) (bs : List Val) :
    (yamlEncList (a :: b :: bs)).length
      = (yamlEnc a).length + (yamlEncList (b :: bs)).length + 2 := by
  simp [yamlEncList]
  omega

theorem yamlEncFields_length_single (k : List Char) (v : Val) :
    (yamlEncFields [(k, v)]).length = (esc k).length + (yamlEnc v).length + 4 := by
  simp [yamlEncFields]
  omega

theorem yamlEncFields_length_cons (k : List Char) (v : Val) (b : List Char × Val)
    (bs : List (List Char × Val)) :
    (yamlEncFields ((k, v) :: b :: bs)).length
      = (esc k).length + (yamlEnc v).length + (yamlEncFields (b :: bs)).length + 6 := by
  simp [yamlEncFields]
  omega

theorem yamlEnc_head (v : Val) :
    ∃ c t, yamlEnc v = c :: t ∧ c ≠ ']' ∧ c ≠ '}' := by
  cases v with
  | null => exact ⟨'n', ['u', 'l', 'l'], rfl, by decide, by decide⟩
  | bool b =>
      cases b
      · exact ⟨'f', ['a', 'l', 's', 'e'], rfl, by decide, by decide⟩
      · exact ⟨'t', ['r', 'u', 'e'], rfl, by decide, by decide⟩
  | int n =>
      obtain ⟨c, cs, hcs, hc⟩ := natDigits_head n.natAbs
      by_cases h : n < 0
      · exact ⟨'-', natDigits n.natAbs, by simp [yamlEnc, encNumY, h], by decide, by decide⟩
      · refine ⟨c, cs, by simp [yamlEnc, encNumY, h, hcs], ?_, ?_⟩ <;>
          (intro hce; rw [hce] at hc; exact hc (by decide))
  | str s => exact ⟨'"', esc s ++ ['"'], rfl, by decide, by decide⟩
  | list xs => exact ⟨'[', yamlEncList xs ++ [']'], rfl, by decide, by decide⟩
  | obj fs => exact ⟨'{', yamlEncFields fs ++ ['}'], rfl, by decide, by decide⟩

theorem yamlEncList_head (a : Val) (as : List Val) :
    ∃ c t, yamlEncList (a :: as) = c :: t ∧ c ≠ ']' := by
  obtain ⟨c, t, hc, hne, _⟩ := yamlEnc_head a
  cases as with
  | nil => exact ⟨c, t, by simpa [yamlEncList] using hc, hne⟩
  | cons b bs =>
      refine ⟨c, t ++ ',' :: ' ' :: yamlEncList (b :: bs), ?_, hne⟩
      simp [yamlEncList, hc]

/-- The round-trip property of one value under the YAML codec. -/
def YRoundTrips (v : Val) : Prop :=
  ∀ fuel rest, (yamlEnc v).length ≤ fuel → NotDigit rest →
    yVal fuel (yamlEnc v ++ rest) = some (v, rest)

theorem yList_roundTrip (xs : List Val) (h : ∀ v ∈ xs, YRoundTrips v) :
    ∀ fuel rest, (yamlEncList xs).length + 1 ≤ fuel →
      yList fuel (yamlEncList xs ++ ']' :: rest) = some (xs, rest) := by
  induction xs with
  | nil =>
      intro fuel rest hlen
      cases fuel with
      | zero => simp [yamlEncList] at hlen
      | succ f => simp [yamlEncList, yList.eq_def]
  | cons a as ih =>
      intro fuel rest hlen
      cases fuel with
      | zero => simp at hlen
      | succ f =>
          obtain ⟨c, t, hct, hcne⟩ := yamlEncList_head a as
          cases as with
          | nil =>
              have hlen' : (yamlEnc a).length + 1 ≤ f + 1 := by
                have := yamlEncList_length_single a
                omega
              have hhead := h a (by simp) f (']' :: rest) (by omega) (by simp [NotDigit, digitVal])
              have hcat : yamlEncList [a] ++ ']' :: rest = c :: (t ++ ']' :: rest) := by
                rw [hct]; simp
              have hfold : c :: (t ++ ']' :: rest) = yamlEnc a ++ ']' :: rest := by
                rw [← List.cons_append, ← hct]
                simp [yamlEncList]
              rw [hcat, yList.eq_def]
              simp only [if_neg hcne, hfold, hhead]
          | cons b bs =>
              have hlen' : (yamlEnc a).length + ((yamlEncList (b :: bs)).length + 2) ≤ f + 1 := by
                have := yamlEncList_length_cons a b bs
                omega
              have hhead := h a (by simp) f (',' :: ' ' :: (yamlEncList (b :: bs) ++ ']' :: rest))
                (by omega) (by simp [NotDigit, digitVal])
              have htail := ih (fun v hv => h v (by simp [hv])) f rest (by omega)
              have hbody : yamlEncList (a :: b :: bs) ++ ']' :: rest
                  = yamlEnc a ++ (',' :: ' ' :: (yamlEncList (b :: bs) ++ ']' :: rest)) := by
                simp [yamlEncList]
              have hcat : yamlEncList (a :: b :: bs) ++ ']' :: rest = c :: (t ++ ']' :: rest) := by
                rw [hct]; simp
              have hfold : c :: (t ++ ']' :: rest)
                  = yamlEnc a ++ (',' :: ' ' :: (yamlEncList (b :: bs) ++ ']' :: rest)) := by
                rw [← List.cons_append, ← hct, hbody]
              rw [hcat, yList.eq_def]
              simp only [if_neg hcne, hfold, hhead, htail]

theorem yFields_roundTrip (fs : List (List Char × Val)) (h : ∀ kv ∈ fs, YRoundTrips kv.2) :
    ∀ fuel rest, (yamlEncFields fs).length + 1 ≤ fuel →
      yFields fuel (yamlEncFields fs ++ '}' :: rest) = some (fs, rest) := by
  induction fs with
  | nil =>
      intro fuel rest hlen
      cases fuel with
      | zero => simp [yamlEncFields] at hlen
      | succ f => simp [yamlEncFields, yFields.eq_def]
  | cons a as ih =>
      intro fuel rest hlen
      obtain ⟨k, v⟩ := a
      cases fuel with
      | zero => simp at hlen
      | succ f =>
          cases as with
          | nil =>
              have hlen' : (esc k).length + ((yamlEnc v).length + 4) ≤ f + 1 := by
                have := yamlEncFields_length_single k v
                omega
              have hkey := readQuoted_esc k (':' :: ' ' :: (yamlEnc v ++ '}' :: rest))
              have hval : yVal f (yamlEnc v ++ '}' :: rest) = some (v, '}' :: rest) :=
                h (k, v) (by simp) f ('}' :: rest)
                  (show (yamlEnc v).length ≤ f from by omega)
                  (by simp [NotDigit, digitVal])
              have hcat : yamlEncFields [(k, v)] ++ '}' :: rest
                  = '"' :: (esc k ++ '"' :: ':' :: ' ' :: (yamlEnc v ++ '}' :: rest)) := by
                simp [yamlEncFields]
              rw [hcat, yFields.eq_def]
              simp [hkey, hval]
          | cons b bs =>
              have hlen' : (esc k).length
                  + ((yamlEnc v).length + ((yamlEncFields (b :: bs)).length + 5)) ≤ f + 1 := by
                have := yamlEncFields_length_cons k v b bs
                omega
              have hkey := readQuoted_esc k
                (':' :: ' ' :: (yamlEnc v ++ ',' :: ' ' :: (yamlEncFields (b :: bs) ++ '}' :: rest)))
              have hval : yVal f (yamlEnc v ++ ',' :: ' ' :: (yamlEncFields (b :: bs) ++ '}' :: rest))
                  = some (v, ',' :: ' ' :: (yamlEncFields (b :: bs) ++ '}' :: rest)) :=
                h (k, v) (by simp) f
                  (',' :: ' ' :: (yamlEncFields (b :: bs) ++ '}' :: rest))
                  (show (yamlEnc v).length ≤ f from by omega)
                  (by simp [NotDigit, digitVal])
              have htail := ih (fun kv hkv => h kv (by simp [hkv])) f rest (by omega)
              have hcat : yamlEncFields ((k, v) :: b :: bs) ++ '}' :: rest
                  = '"' :: (esc k ++ '"' :: ':' :: ' ' ::
                      (yamlEnc v ++ ',' :: ' ' :: (yamlEncFields (b :: bs) ++ '}' :: rest))) := by
                simp [yamlEncFields]
              rw [hcat, yFields.eq_def]
              simp [hkey, hval, htail]

theorem yVal_yamlEnc (v : Val) : YRoundTrips v := by
  induction v using Val.strong with
  | hnull =>
      intro fuel rest hlen _
      cases fuel with
      | zero => simp [yamlEnc] at hlen
      | succ f => simp [yamlEnc, yVal.eq_def]
  | hbool b =>
      intro fuel rest hlen _
      cases fuel with
      | zero => cases b <;> simp [yamlEnc] at hlen
      | succ f => cases b <;> simp [yamlEnc, yVal.eq_def]
  | hint n =>
      intro fuel rest hlen hr
      cases fuel with
      | zero =>
          have : 0 < (yamlEnc (Val.int n)).length := by
            obtain ⟨c, t, hct, _, _⟩ := yamlEnc_head (Val.int n)
            rw [hct]; simp
          omega
      | succ f =>
          obtain ⟨c, t, hct, _, _⟩ := yamlEnc_head (Val.int n)
          have hnum := readNumY_encNumY n rest hr
          have hyv : yamlEnc (Val.int n) = encNumY n := rfl
          rw [hyv] at hct ⊢
          have hc : c ≠ '"' ∧ c ≠ '[' ∧ c ≠ '{' ∧ c ≠ 'n' ∧ c ≠ 't' ∧ c ≠ 'f' := by
            by_cases hneg : n < 0
            · have : c = '-' := by
                have := hct
                rw [encNumY, if_pos hneg] at this
                exact (List.cons.inj this).1.symm ▸ rfl
              subst this
              exact ⟨by decide, by decide, by decide, by decide, by decide, by decide⟩
            · obtain ⟨d, ds, hds, hdv⟩ := natDigits_head n.natAbs
              have hcd : c = d := by
                have := hct
                rw [encNumY, if_neg hneg, hds] at this
                exact (List.cons.inj this).1.symm
              subst hcd
              refine ⟨?_, ?_, ?_, ?_, ?_, ?_⟩ <;>
                (intro hce; rw [hce] at hdv; exact hdv (by decide))
          obtain ⟨h1, h2, h3, h4, h5, h6⟩ := hc
          have hcat : encNumY n ++ rest = c :: (t ++ rest) := by rw [hct]; simp
          have hback : c :: (t ++ rest) = encNumY n ++ rest := hcat.symm
          rw [hcat, yVal.eq_def]
          simp only [if_neg h1, if_neg h2, if_neg h3, if_neg h4, if_neg h5, if_neg h6,
            hback, hnum, Option.map_some]
  | hstr s =>
      intro fuel rest hlen _
      cases fuel with
      | zero => simp [yamlEnc] at hlen
      | succ f =>
          have hcat : yamlEnc (Val.str s) ++ rest = '"' :: (esc s ++ '"' :: rest) := by
            simp [yamlEnc]
          rw [hcat, yVal.eq_def]
          simp [readQuoted_esc]
  | hlist xs hxs =>
      intro fuel rest hlen _
      cases fuel with
      | zero => simp [yamlEnc] at hlen
      | succ f =>
          have hlen' : (yamlEncList xs).length + 1 ≤ f := by
            simp [yamlEnc] at hlen; omega
          have hbody := yList_roundTrip xs hxs f rest (by omega)
          have hcat : yamlEnc (Val.list xs) ++ rest = '[' :: (yamlEncList xs ++ ']' :: rest) := by
            simp [yamlEnc]
          rw [hcat, yVal.eq_def]
          simp [hbody]
  | hobj fs hfs =>
      intro fuel rest hlen _
      cases fuel with
      | zero => simp [yamlEnc] at hlen
      | succ f =>
          have hlen' : (yamlEncFields fs).length + 1 ≤ f := by
            simp [yamlEnc] at hlen; omega
          have hbody := yFields_roundTrip fs hfs f rest (by omega)
          have hcat : yamlEnc (Val.obj fs) ++ rest = '{' :: (yamlEncFields fs ++ '}' :: rest) := by
            simp [yamlEnc]
          rw [hcat, yVal.eq_def]
          simp [hbody]

/-- The YAML decoder: parse one value and insist the document is fully
consumed. -/
def yamlDecode (s : List Char) : Option Val :=
  match yVal s.length s with
  | some (v, []) => some v
  | _ => none

/-- **YAML round-trips.** -/
theorem yamlDecode_yamlEnc (v : Val) : yamlDecode (yamlEnc v) = some v := by
  have h := yVal_yamlEnc v (yamlEnc v).length [] (by simp) (by simp [NotDigit])
  simp only [List.append_nil] at h
  simp [yamlDecode, h]

/-- **The YAML projection is injective**, so `Canonical → YAML →
Canonical` is lossless. -/
theorem yamlEnc_injective {a b : Val} (h : yamlEnc a = yamlEnc b) : a = b := by
  have ha := yamlDecode_yamlEnc a
  rw [h, yamlDecode_yamlEnc b] at ha
  exact (Option.some.inj ha).symm

end Kant.Codec
