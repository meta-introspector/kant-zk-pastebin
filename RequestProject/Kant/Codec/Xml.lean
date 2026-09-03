/-
# The XML codec

XML carries the canonical model as elements, with the distinction between
*element*, *attribute* and *text node* preserved: a mapping entry is an
`<entry key="…">` element whose key lives in an attribute and whose value
is the child element, and a string is a text node with the five XML
entities escaped.

Proved here:

* `readXText_xesc` — text nodes round-trip: escaping and unescaping are
  inverse, for every string;
* `xmlDecode_xmlEnc` — **XML round-trips**, for every canonical value;
* `xmlEnc_injective` — so `Canonical → XML → Canonical` is `LOSSLESS`.
-/
import Mathlib
import RequestProject.Kant.Codec.Val
import RequestProject.Kant.Codec.Yaml

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.Codec

/-! ## Tags -/

/-- `<null/>` -/
def xNull : List Char := ['<', 'n', 'u', 'l', 'l', '/', '>']
/-- `<bool>true</bool>` -/
def xTrue : List Char :=
  ['<', 'b', 'o', 'o', 'l', '>', 't', 'r', 'u', 'e', '<', '/', 'b', 'o', 'o', 'l', '>']
/-- `<bool>false</bool>` -/
def xFalse : List Char :=
  ['<', 'b', 'o', 'o', 'l', '>', 'f', 'a', 'l', 's', 'e', '<', '/', 'b', 'o', 'o', 'l', '>']
/-- `<int>` -/
def xIntOpen : List Char := ['<', 'i', 'n', 't', '>']
/-- `</int>` -/
def xIntClose : List Char := ['<', '/', 'i', 'n', 't', '>']
/-- `<str>` -/
def xStrOpen : List Char := ['<', 's', 't', 'r', '>']
/-- `</str>` -/
def xStrClose : List Char := ['<', '/', 's', 't', 'r', '>']
/-- `<list>` -/
def xListOpen : List Char := ['<', 'l', 'i', 's', 't', '>']
/-- `</list>` -/
def xListClose : List Char := ['<', '/', 'l', 'i', 's', 't', '>']
/-- `<obj>` -/
def xObjOpen : List Char := ['<', 'o', 'b', 'j', '>']
/-- `</obj>` -/
def xObjClose : List Char := ['<', '/', 'o', 'b', 'j', '>']
/-- `<entry key="` -/
def xEntryOpen : List Char := ['<', 'e', 'n', 't', 'r', 'y', ' ', 'k', 'e', 'y', '=', '"']
/-- `">` -/
def xEntryMid : List Char := ['"', '>']
/-- `</entry>` -/
def xEntryClose : List Char := ['<', '/', 'e', 'n', 't', 'r', 'y', '>']

/-- Stripping a literal prefix. -/
def stripPrefix : List Char → List Char → Option (List Char)
  | [], s => some s
  | _ :: _, [] => none
  | p :: ps, c :: cs => if p = c then stripPrefix ps cs else none

@[simp] theorem stripPrefix_append (p r : List Char) : stripPrefix p (p ++ r) = some r := by
  induction p with
  | nil => rfl
  | cons c cs ih => simpa [stripPrefix] using ih

theorem stripPrefix_cons_ne {p c : Char} {ps t : List Char} (h : p ≠ c) :
    stripPrefix (p :: ps) (c :: t) = none := by
  simp [stripPrefix, h]

/-! ## Text nodes -/

/-- One character, escaped as XML character data. -/
def xescChar (c : Char) : List Char :=
  if c = '&' then ['&', 'a', 'm', 'p', ';']
  else if c = '<' then ['&', 'l', 't', ';']
  else if c = '>' then ['&', 'g', 't', ';']
  else if c = '"' then ['&', 'q', 'u', 'o', 't', ';']
  else if c = '\'' then ['&', 'a', 'p', 'o', 's', ';']
  else [c]

/-- A string, escaped as XML character data. -/
def xesc (s : List Char) : List Char := s.flatMap xescChar

/-- Reading escaped character data, up to the next occurrence of the
terminator (`<` for a text node, `"` for an attribute value).  Both
terminators are themselves escaped by `xesc`, so the stop is unambiguous. -/
def readXUntil (term : Char) : List Char → Option (List Char × List Char)
  | [] => some ([], [])
  | '&' :: 'a' :: 'm' :: 'p' :: ';' :: rest =>
      (readXUntil term rest).map (fun p => ('&' :: p.1, p.2))
  | '&' :: 'l' :: 't' :: ';' :: rest => (readXUntil term rest).map (fun p => ('<' :: p.1, p.2))
  | '&' :: 'g' :: 't' :: ';' :: rest => (readXUntil term rest).map (fun p => ('>' :: p.1, p.2))
  | '&' :: 'q' :: 'u' :: 'o' :: 't' :: ';' :: rest =>
      (readXUntil term rest).map (fun p => ('"' :: p.1, p.2))
  | '&' :: 'a' :: 'p' :: 'o' :: 's' :: ';' :: rest =>
      (readXUntil term rest).map (fun p => ('\'' :: p.1, p.2))
  | '&' :: _ => none
  | c :: rest =>
      if c = term then some ([], c :: rest)
      else (readXUntil term rest).map (fun p => (c :: p.1, p.2))

/-- **Escaped character data round-trips**, for every string. -/
theorem readXUntil_xesc {term : Char} (hterm : term = '<' ∨ term = '"') (s rest : List Char) :
    readXUntil term (xesc s ++ term :: rest) = some (s, term :: rest) := by
  induction s with
  | nil =>
      have : xesc [] ++ term :: rest = term :: rest := by simp [xesc]
      rw [this, readXUntil.eq_def]
      rcases hterm with rfl | rfl <;> simp
  | cons c cs ih =>
      have hcat : xesc (c :: cs) ++ term :: rest = xescChar c ++ (xesc cs ++ term :: rest) := by
        simp [xesc, List.flatMap_cons]
      rw [hcat]
      by_cases h1 : c = '&'
      · subst h1
        simp only [xescChar]
        rw [readXUntil.eq_def]
        simp [ih]
      · by_cases h2 : c = '<'
        · subst h2
          simp only [xescChar, if_neg h1]
          rw [readXUntil.eq_def]
          simp [ih]
        · by_cases h3 : c = '>'
          · subst h3
            simp only [xescChar, if_neg h1, if_neg h2]
            rw [readXUntil.eq_def]
            simp [ih]
          · by_cases h4 : c = '"'
            · subst h4
              simp only [xescChar, if_neg h1, if_neg h2, if_neg h3]
              rw [readXUntil.eq_def]
              simp [ih]
            · by_cases h5 : c = '\''
              · subst h5
                simp only [xescChar, if_neg h1, if_neg h2, if_neg h3, if_neg h4]
                rw [readXUntil.eq_def]
                simp [ih]
              · have hcc : xescChar c = [c] := by simp [xescChar, h1, h2, h3, h4, h5]
                have hct : c ≠ term := by rcases hterm with rfl | rfl <;> assumption
                rw [hcc]
                simp only [List.cons_append, List.nil_append]
                rw [readXUntil.eq_def]
                simp [h1, hct, ih]

/-- Reading a text node, up to the next `<`. -/
def readXText (s : List Char) : Option (List Char × List Char) := readXUntil '<' s

/-- Reading an attribute value, up to the closing quote. -/
def readXAttr (s : List Char) : Option (List Char × List Char) := readXUntil '"' s

theorem readXText_xesc (s rest : List Char) :
    readXText (xesc s ++ '<' :: rest) = some (s, '<' :: rest) :=
  readXUntil_xesc (Or.inl rfl) s rest

theorem readXAttr_xesc (s rest : List Char) :
    readXAttr (xesc s ++ '"' :: rest) = some (s, '"' :: rest) :=
  readXUntil_xesc (Or.inr rfl) s rest

/-! ## The XML projection -/

mutual

/-- A canonical value as XML. -/
def xmlEnc : Val → List Char
  | .null => xNull
  | .bool true => xTrue
  | .bool false => xFalse
  | .int n => xIntOpen ++ (encNumY n ++ xIntClose)
  | .str s => xStrOpen ++ (xesc s ++ xStrClose)
  | .list xs => xListOpen ++ (xmlEncList xs ++ xListClose)
  | .obj fs => xObjOpen ++ (xmlEncFields fs ++ xObjClose)

/-- The children of a `<list>`. -/
def xmlEncList : List Val → List Char
  | [] => []
  | v :: vs => xmlEnc v ++ xmlEncList vs

/-- The entries of an `<obj>`. -/
def xmlEncFields : List (List Char × Val) → List Char
  | [] => []
  | (k, v) :: fs =>
      xEntryOpen ++ (xesc k ++ (xEntryMid ++ (xmlEnc v ++ (xEntryClose ++ xmlEncFields fs))))

end

mutual

/-- The XML parser. -/
def xVal : Nat → List Char → Option (Val × List Char)
  | 0, _ => none
  | fuel + 1, s =>
      match stripPrefix xNull s with
      | some r => some (Val.null, r)
      | none =>
        match stripPrefix xTrue s with
        | some r => some (Val.bool true, r)
        | none =>
          match stripPrefix xFalse s with
          | some r => some (Val.bool false, r)
          | none =>
            match stripPrefix xIntOpen s with
            | some r0 =>
                (readNumY r0).bind (fun p =>
                  (stripPrefix xIntClose p.2).map (fun r => (Val.int p.1, r)))
            | none =>
              match stripPrefix xStrOpen s with
              | some r0 =>
                  (readXText r0).bind (fun p =>
                    (stripPrefix xStrClose p.2).map (fun r => (Val.str p.1, r)))
              | none =>
                match stripPrefix xListOpen s with
                | some r0 => (xList fuel r0).map (fun p => (Val.list p.1, p.2))
                | none =>
                  match stripPrefix xObjOpen s with
                  | some r0 => (xFields fuel r0).map (fun p => (Val.obj p.1, p.2))
                  | none => none
  termination_by fuel _ => (fuel, 1)

/-- The children of a `<list>`, up to the closing tag. -/
def xList : Nat → List Char → Option (List Val × List Char)
  | 0, _ => none
  | fuel + 1, s =>
      match stripPrefix xListClose s with
      | some r => some ([], r)
      | none =>
        match xVal fuel s with
        | some (v, r) => (xList fuel r).map (fun p => (v :: p.1, p.2))
        | none => none
  termination_by fuel _ => (fuel, 0)

/-- The entries of an `<obj>`, up to the closing tag. -/
def xFields : Nat → List Char → Option (List (List Char × Val) × List Char)
  | 0, _ => none
  | fuel + 1, s =>
      match stripPrefix xObjClose s with
      | some r => some ([], r)
      | none =>
        match stripPrefix xEntryOpen s with
        | some r0 =>
            match readXAttr r0 with
            | some (k, r1) =>
                match stripPrefix xEntryMid r1 with
                | some r2 =>
                    match xVal fuel r2 with
                    | some (v, r3) =>
                        match stripPrefix xEntryClose r3 with
                        | some r4 => (xFields fuel r4).map (fun p => ((k, v) :: p.1, p.2))
                        | none => none
                    | none => none
                | none => none
            | none => none
        | none => none
  termination_by fuel _ => (fuel, 0)

end

/-! ## The round trip -/

/-- Every encoding opens with `<` and a letter, so a closing tag can never
be mistaken for the start of a value. -/
theorem xmlEnc_head (v : Val) : ∃ c t, xmlEnc v = '<' :: c :: t ∧ c ≠ '/' := by
  cases v with
  | null => exact ⟨'n', ['u', 'l', 'l', '/', '>'], rfl, by decide⟩
  | bool b =>
      cases b
      · exact ⟨'b', ['o', 'o', 'l', '>', 'f', 'a', 'l', 's', 'e', '<', '/', 'b', 'o', 'o', 'l', '>'],
          rfl, by decide⟩
      · exact ⟨'b', ['o', 'o', 'l', '>', 't', 'r', 'u', 'e', '<', '/', 'b', 'o', 'o', 'l', '>'],
          rfl, by decide⟩
  | int n => exact ⟨'i', ['n', 't', '>'] ++ (encNumY n ++ xIntClose), rfl, by decide⟩
  | str s => exact ⟨'s', ['t', 'r', '>'] ++ (xesc s ++ xStrClose), rfl, by decide⟩
  | list xs => exact ⟨'l', ['i', 's', 't', '>'] ++ (xmlEncList xs ++ xListClose), rfl, by decide⟩
  | obj fs => exact ⟨'o', ['b', 'j', '>'] ++ (xmlEncFields fs ++ xObjClose), rfl, by decide⟩

theorem stripPrefix_close_of_head {v : Val} {rest : List Char} :
    stripPrefix xListClose (xmlEnc v ++ rest) = none := by
  obtain ⟨c, t, hct, hc⟩ := xmlEnc_head v
  rw [hct]
  simp [xListClose, stripPrefix, Ne.symm hc]

theorem stripPrefix_objClose_entry (k : List Char) (v : Val) (fs : List (List Char × Val))
    (rest : List Char) :
    stripPrefix xObjClose (xmlEncFields ((k, v) :: fs) ++ rest) = none := by
  simp [xmlEncFields, xObjClose, xEntryOpen, stripPrefix]

theorem stripPrefix_objClose_entry_aux (rest : List Char) :
    stripPrefix xObjClose (xEntryOpen ++ rest) = none := by
  simp [xObjClose, xEntryOpen, stripPrefix]

/-- The round-trip property of one value under the XML codec. -/
def XRoundTrips (v : Val) : Prop :=
  ∀ fuel rest, (xmlEnc v).length ≤ fuel → xVal fuel (xmlEnc v ++ rest) = some (v, rest)

theorem xList_roundTrip (xs : List Val) (h : ∀ v ∈ xs, XRoundTrips v) :
    ∀ fuel rest, (xmlEncList xs).length + 1 ≤ fuel →
      xList fuel (xmlEncList xs ++ (xListClose ++ rest)) = some (xs, rest) := by
  induction xs with
  | nil =>
      intro fuel rest hlen
      cases fuel with
      | zero => simp [xmlEncList] at hlen
      | succ f => simp [xmlEncList, xList.eq_def]
  | cons a as ih =>
      intro fuel rest hlen
      cases fuel with
      | zero => simp at hlen
      | succ f =>
          have hcat : xmlEncList (a :: as) ++ (xListClose ++ rest)
              = xmlEnc a ++ (xmlEncList as ++ (xListClose ++ rest)) := by
            simp [xmlEncList]
          have hlen' : (xmlEnc a).length + (xmlEncList as).length + 1 ≤ f + 1 := by
            have : (xmlEncList (a :: as)).length = (xmlEnc a).length + (xmlEncList as).length := by
              simp [xmlEncList]
            omega
          have hpos : 0 < (xmlEnc a).length := by
            obtain ⟨c, t, hct, _⟩ := xmlEnc_head a
            rw [hct]; simp
          have hhead := h a (by simp) f (xmlEncList as ++ (xListClose ++ rest)) (by omega)
          have htail := ih (fun v hv => h v (by simp [hv])) f rest (by omega)
          rw [hcat, xList.eq_def]
          simp only [stripPrefix_close_of_head, hhead, htail, Option.map_some]

theorem xFields_roundTrip (fs : List (List Char × Val)) (h : ∀ kv ∈ fs, XRoundTrips kv.2) :
    ∀ fuel rest, (xmlEncFields fs).length + 1 ≤ fuel →
      xFields fuel (xmlEncFields fs ++ (xObjClose ++ rest)) = some (fs, rest) := by
  induction fs with
  | nil =>
      intro fuel rest hlen
      cases fuel with
      | zero => simp [xmlEncFields] at hlen
      | succ f => simp [xmlEncFields, xFields.eq_def]
  | cons a as ih =>
      intro fuel rest hlen
      obtain ⟨k, v⟩ := a
      cases fuel with
      | zero => simp at hlen
      | succ f =>
          have hlen' : (xesc k).length + (xmlEnc v).length + (xmlEncFields as).length + 21
              ≤ f + 1 := by
            have hl : (xmlEncFields ((k, v) :: as)).length
                = (xesc k).length + (xmlEnc v).length + (xmlEncFields as).length + 22 := by
              simp [xmlEncFields, xEntryOpen, xEntryMid, xEntryClose]
              omega
            omega
          have hkey := readXAttr_xesc k
            ('>' :: (xmlEnc v ++ (xEntryClose ++ (xmlEncFields as ++ (xObjClose ++ rest)))))
          have hval : xVal f (xmlEnc v ++ (xEntryClose ++ (xmlEncFields as ++ (xObjClose ++ rest))))
              = some (v, xEntryClose ++ (xmlEncFields as ++ (xObjClose ++ rest))) :=
            h (k, v) (by simp) f _ (show (xmlEnc v).length ≤ f from by omega)
          have htail := ih (fun kv hkv => h kv (by simp [hkv])) f rest (by omega)
          have hcat : xmlEncFields ((k, v) :: as) ++ (xObjClose ++ rest)
              = xEntryOpen ++ (xesc k ++ ('"' :: ['>'] ++
                  (xmlEnc v ++ (xEntryClose ++ (xmlEncFields as ++ (xObjClose ++ rest)))))) := by
            simp [xmlEncFields, xEntryMid]
          rw [hcat, xFields.eq_def]
          simp only [stripPrefix_objClose_entry_aux, stripPrefix_append, List.cons_append,
            List.nil_append, hkey]
          simp [xEntryMid, stripPrefix, hval, htail]

theorem xVal_xmlEnc (v : Val) : XRoundTrips v := by
  induction v using Val.strong with
  | hnull =>
      intro fuel rest hlen
      cases fuel with
      | zero => simp [xmlEnc, xNull] at hlen
      | succ f => simp [xmlEnc, xVal.eq_def]
  | hbool b =>
      intro fuel rest hlen
      cases fuel with
      | zero => cases b <;> simp [xmlEnc, xTrue, xFalse] at hlen
      | succ f =>
          cases b
          · simp [xmlEnc, xVal.eq_def, xNull, xTrue, xFalse, stripPrefix]
          · simp [xmlEnc, xVal.eq_def, xNull, xTrue, stripPrefix]
  | hint n =>
      intro fuel rest hlen
      cases fuel with
      | zero => simp [xmlEnc, xIntOpen] at hlen
      | succ f =>
          have hnum : readNumY (encNumY n ++ (xIntClose ++ rest)) = some (n, xIntClose ++ rest) :=
            readNumY_encNumY n _ (by simp [NotDigit, xIntClose, digitVal])
          have hcat : xmlEnc (Val.int n) ++ rest = xIntOpen ++ (encNumY n ++ (xIntClose ++ rest)) := by
            simp [xmlEnc]
          rw [hcat, xVal.eq_def]
          simp [xNull, xTrue, xFalse, xIntOpen, stripPrefix, hnum]
  | hstr s =>
      intro fuel rest hlen
      cases fuel with
      | zero => simp [xmlEnc, xStrOpen] at hlen
      | succ f =>
          have hcat : xmlEnc (Val.str s) ++ rest = xStrOpen ++ (xesc s ++ (xStrClose ++ rest)) := by
            simp [xmlEnc]
          have htext : readXText (xesc s ++ (xStrClose ++ rest)) = some (s, xStrClose ++ rest) := by
            have := readXText_xesc s (['/', 's', 't', 'r', '>'] ++ rest)
            simpa [xStrClose] using this
          rw [hcat, xVal.eq_def]
          simp [xNull, xTrue, xFalse, xIntOpen, xStrOpen, stripPrefix, htext]
  | hlist xs hxs =>
      intro fuel rest hlen
      cases fuel with
      | zero => simp [xmlEnc, xListOpen] at hlen
      | succ f =>
          have hlen' : (xmlEncList xs).length + 1 ≤ f := by
            have : (xmlEnc (Val.list xs)).length
                = (xmlEncList xs).length + (xListOpen.length + xListClose.length) := by
              simp [xmlEnc]
              omega
            simp [xListOpen, xListClose] at this
            omega
          have hbody := xList_roundTrip xs hxs f rest (by omega)
          have hcat : xmlEnc (Val.list xs) ++ rest
              = xListOpen ++ (xmlEncList xs ++ (xListClose ++ rest)) := by
            simp [xmlEnc]
          rw [hcat, xVal.eq_def]
          simp [xNull, xTrue, xFalse, xIntOpen, xStrOpen, xListOpen, stripPrefix, hbody]
  | hobj fs hfs =>
      intro fuel rest hlen
      cases fuel with
      | zero => simp [xmlEnc, xObjOpen] at hlen
      | succ f =>
          have hlen' : (xmlEncFields fs).length + 1 ≤ f := by
            have : (xmlEnc (Val.obj fs)).length
                = (xmlEncFields fs).length + (xObjOpen.length + xObjClose.length) := by
              simp [xmlEnc]
              omega
            simp [xObjOpen, xObjClose] at this
            omega
          have hbody := xFields_roundTrip fs hfs f rest (by omega)
          have hcat : xmlEnc (Val.obj fs) ++ rest
              = xObjOpen ++ (xmlEncFields fs ++ (xObjClose ++ rest)) := by
            simp [xmlEnc]
          rw [hcat, xVal.eq_def]
          simp [xNull, xTrue, xFalse, xIntOpen, xStrOpen, xListOpen, xObjOpen, stripPrefix, hbody]

/-- The XML decoder: parse one element and insist the document is fully
consumed. -/
def xmlDecode (s : List Char) : Option Val :=
  match xVal s.length s with
  | some (v, []) => some v
  | _ => none

/-- **XML round-trips.** -/
theorem xmlDecode_xmlEnc (v : Val) : xmlDecode (xmlEnc v) = some v := by
  have h := xVal_xmlEnc v (xmlEnc v).length [] (by simp)
  simp only [List.append_nil] at h
  simp [xmlDecode, h]

/-- **The XML projection is injective**, so `Canonical → XML → Canonical`
is lossless. -/
theorem xmlEnc_injective {a b : Val} (h : xmlEnc a = xmlEnc b) : a = b := by
  have ha := xmlDecode_xmlEnc a
  rw [h, xmlDecode_xmlEnc b] at ha
  exact (Option.some.inj ha).symm

end Kant.Codec
