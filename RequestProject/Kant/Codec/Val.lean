/-
# The canonical model of the standard proof codec

The exchange standard says: *never make one external format the canonical
representation*.  Everything that travels between proof systems is first
decoded into one semantic object, and every format — IPDL, XML, CSV, YAML,
raw text — is an adapter to and from that object.

This module is the bottom of that stack: the **canonical value**, the tree
of nulls, booleans, integers, strings, lists and keyed objects that every
codec in `Kant.Codec` reads and writes, together with

* `canonEnc` / `canonDecode` — the *canonical serialization*: a
  deterministic, length-prefixed form suitable for hashing;
* `canonDecode_canonEnc` — it round-trips for **every** value, with no
  side conditions at all;
* `canonEnc_injective` — the serialization is injective, so the content
  hash `valHash` of it is a stable identity (`valHash_eq_of_eq`,
  `ne_of_valHash_ne`).
-/
import Mathlib
import RequestProject.Kant.Bytes
import RequestProject.Kant.Text

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.Codec

open Kant.Bytes

/-! ## The canonical value -/

/-- A value of the canonical model.  Structured data (`obj`, `list`),
semi-structured data (objects carrying free-form extension keys) and
unstructured data (`str`) all live in the same tree. -/
inductive Val where
  | null
  | bool (b : Bool)
  | int (n : Int)
  | str (s : List Char)
  | list (xs : List Val)
  | obj (fs : List (List Char × Val))
deriving Repr, Inhabited

namespace Val

/-- Explicit null handling: whether a value is the canonical null. -/
def isNull : Val → Bool
  | .null => true
  | _ => false

/-- Induction over a value, with the nested lists handled by membership
hypotheses. -/
@[elab_as_elim]
theorem strong {motive : Val → Prop}
    (hnull : motive .null) (hbool : ∀ b, motive (.bool b)) (hint : ∀ n, motive (.int n))
    (hstr : ∀ s, motive (.str s))
    (hlist : ∀ xs, (∀ v ∈ xs, motive v) → motive (.list xs))
    (hobj : ∀ fs, (∀ kv ∈ fs, motive kv.2) → motive (.obj fs)) : ∀ v, motive v := by
  intro v
  refine Val.rec (motive_1 := motive) (motive_2 := fun xs => ∀ v ∈ xs, motive v)
    (motive_3 := fun fs => ∀ kv ∈ fs, motive kv.2) (motive_4 := fun kv => motive kv.2)
    hnull hbool hint hstr hlist hobj ?_ ?_ ?_ ?_ ?_ v
  · intro v hv; exact absurd hv (by simp)
  · intro a as ha has v hv
    rcases List.mem_cons.1 hv with h | h
    · exact h ▸ ha
    · exact has v h
  · intro kv hkv; exact absurd hkv (by simp)
  · intro a as ha has kv hkv
    rcases List.mem_cons.1 hkv with h | h
    · exact h ▸ ha
    · exact has kv h
  · intro _ v hv; exact hv

end Val

/-! ## Decimal digits

Numbers are written in plain decimal and terminated by `;`, so a reader
never has to look past the number it is reading. -/

/-- The character of a decimal digit. -/
def digitChar : Nat → Char
  | 0 => '0' | 1 => '1' | 2 => '2' | 3 => '3' | 4 => '4'
  | 5 => '5' | 6 => '6' | 7 => '7' | 8 => '8' | _ => '9'

/-- The digit a character stands for, if it is one. -/
def digitVal (c : Char) : Option Nat :=
  match c with
  | '0' => some 0 | '1' => some 1 | '2' => some 2 | '3' => some 3 | '4' => some 4
  | '5' => some 5 | '6' => some 6 | '7' => some 7 | '8' => some 8 | '9' => some 9
  | _ => none

theorem digitVal_digitChar {n : Nat} (h : n < 10) : digitVal (digitChar n) = some n := by
  interval_cases n <;> rfl

/-- The decimal digits of a natural number, most significant first. -/
def natDigits (n : Nat) : List Char :=
  if n < 10 then [digitChar n]
  else natDigits (n / 10) ++ [digitChar (n % 10)]
  termination_by n
  decreasing_by omega

/-- The value a list of digit characters denotes, read left to right. -/
def digitsFold (acc : Nat) : List Char → Nat
  | [] => acc
  | c :: cs => digitsFold (acc * 10 + (digitVal c).getD 0) cs

theorem digitsFold_append (acc : Nat) (a b : List Char) :
    digitsFold acc (a ++ b) = digitsFold (digitsFold acc a) b := by
  induction a generalizing acc with
  | nil => rfl
  | cons c cs ih => simpa [digitsFold] using ih _

theorem natDigits_length_pos (n : Nat) : 0 < (natDigits n).length := by
  rw [natDigits]
  by_cases h : n < 10 <;> simp [h]

theorem digitsFold_natDigits (acc n : Nat) :
    digitsFold acc (natDigits n) = acc * 10 ^ (natDigits n).length + n := by
  induction n using Nat.strong_induction_on with
  | _ n ih =>
    rw [natDigits]
    by_cases h : n < 10
    · simp [h, digitsFold, digitVal_digitChar h]
    · have hlt : n / 10 < n := Nat.div_lt_self (by omega) (by norm_num)
      have hm : n % 10 < 10 := Nat.mod_lt _ (by norm_num)
      have hdm : 10 * (n / 10) + n % 10 = n := Nat.div_add_mod' n 10 ▸ by omega
      simp only [h, if_false]
      rw [digitsFold_append, ih _ hlt]
      simp only [digitsFold, digitVal_digitChar hm, Option.getD_some, List.length_append,
        List.length_singleton, pow_succ]
      ring_nf
      omega

theorem natDigits_digits (n : Nat) : ∀ c ∈ natDigits n, digitVal c ≠ none ∧ c ≠ ';' := by
  induction n using Nat.strong_induction_on with
  | _ n ih =>
    rw [natDigits]
    by_cases h : n < 10
    · simp only [h, if_true, List.mem_singleton]
      rintro c rfl
      interval_cases n <;> exact ⟨by decide, by decide⟩
    · have hlt : n / 10 < n := Nat.div_lt_self (by omega) (by norm_num)
      have hm : n % 10 < 10 := Nat.mod_lt _ (by norm_num)
      simp only [h, if_false, List.mem_append, List.mem_singleton]
      rintro c (hc | rfl)
      · exact ih _ hlt c hc
      · interval_cases hn : (n % 10) <;> exact ⟨by decide, by decide⟩

/-- Reading a decimal number up to its terminating `;`. -/
def readNatAux (acc : Nat) : List Char → Option (Nat × List Char)
  | [] => none
  | c :: cs =>
      if c = ';' then some (acc, cs)
      else match digitVal c with
        | some d => readNatAux (acc * 10 + d) cs
        | none => none

/-- Reading a decimal number up to its terminating `;`. -/
def readNat (s : List Char) : Option (Nat × List Char) := readNatAux 0 s

theorem readNatAux_digits (acc : Nat) (ds : List Char)
    (hd : ∀ c ∈ ds, digitVal c ≠ none ∧ c ≠ ';') (rest : List Char) :
    readNatAux acc (ds ++ ';' :: rest) = some (digitsFold acc ds, rest) := by
  induction ds generalizing acc with
  | nil => simp [readNatAux, digitsFold]
  | cons c cs ih =>
      obtain ⟨hcv, hc⟩ := hd c (by simp)
      obtain ⟨d, hdv⟩ := Option.ne_none_iff_exists'.1 hcv
      simp only [List.cons_append, readNatAux, if_neg hc, hdv, digitsFold, Option.getD_some]
      exact ih _ (fun x hx => hd x (List.mem_cons_of_mem _ hx))

/-- **Numbers round-trip.** -/
theorem readNat_natDigits (n : Nat) (rest : List Char) :
    readNat (natDigits n ++ ';' :: rest) = some (n, rest) := by
  rw [readNat, readNatAux_digits 0 _ (natDigits_digits n) rest, digitsFold_natDigits]
  simp

/-! ## Strings and integers -/

/-- A string, length-prefixed: `<len>;<characters>`.  No escaping, so no
character is ever forbidden and nothing can be mistaken for a delimiter. -/
def encStr (s : List Char) : List Char := natDigits s.length ++ ';' :: s

/-- Reading a length-prefixed string. -/
def readStr (s : List Char) : Option (List Char × List Char) :=
  match readNat s with
  | some (n, r) => if n ≤ r.length then some (r.take n, r.drop n) else none
  | none => none

/-- **Strings round-trip**, whatever characters they contain. -/
theorem readStr_encStr (s rest : List Char) : readStr (encStr s ++ rest) = some (s, rest) := by
  have h : encStr s ++ rest = natDigits s.length ++ ';' :: (s ++ rest) := by
    simp [encStr]
  simp [readStr, h, readNat_natDigits]

/-- An integer: an explicit sign, the decimal digits, then `;`. -/
def encInt (n : Int) : List Char :=
  (if n < 0 then '-' else '+') :: (natDigits n.natAbs ++ [';'])

/-- Reading a signed integer. -/
def readInt : List Char → Option (Int × List Char)
  | '-' :: cs => (readNat cs).map (fun p => (-(p.1 : Int), p.2))
  | '+' :: cs => (readNat cs).map (fun p => ((p.1 : Int), p.2))
  | _ => none

/-- **Integers round-trip.** -/
theorem readInt_encInt (n : Int) (rest : List Char) :
    readInt (encInt n ++ rest) = some (n, rest) := by
  by_cases h : n < 0
  · have habs : -((n.natAbs : Int)) = n := by omega
    have hs : encInt n ++ rest = '-' :: (natDigits n.natAbs ++ ';' :: rest) := by
      simp [encInt, h]
    rw [hs, readInt, readNat_natDigits]
    simp only [Option.map_some]
    rw [habs]
  · have habs : ((n.natAbs : Int)) = n := by omega
    have hs : encInt n ++ rest = '+' :: (natDigits n.natAbs ++ ';' :: rest) := by
      simp [encInt, h]
    rw [hs, readInt, readNat_natDigits]
    simp only [Option.map_some]
    rw [habs]

/-! ## The canonical serialization -/

mutual

/-- The canonical serialization of a value: a tag character, then
length-prefixed contents.  Deterministic, and suitable for hashing. -/
def canonEnc : Val → List Char
  | .null => ['Z']
  | .bool true => ['T']
  | .bool false => ['F']
  | .int n => 'I' :: encInt n
  | .str s => 'S' :: encStr s
  | .list xs => 'L' :: (natDigits xs.length ++ ';' :: canonEncList xs)
  | .obj fs => 'O' :: (natDigits fs.length ++ ';' :: canonEncFields fs)

/-- The canonical serialization of the elements of a list. -/
def canonEncList : List Val → List Char
  | [] => []
  | v :: vs => canonEnc v ++ canonEncList vs

/-- The canonical serialization of the fields of an object. -/
def canonEncFields : List (List Char × Val) → List Char
  | [] => []
  | (k, v) :: fs => encStr k ++ canonEnc v ++ canonEncFields fs

end

mutual

/-- The canonical parser.  `fuel` bounds the work; the caller passes the
length of the input, which is always enough. -/
def pVal : Nat → List Char → Option (Val × List Char)
  | 0, _ => none
  | _ + 1, [] => none
  | fuel + 1, c :: rest =>
      if c = 'Z' then some (.null, rest)
      else if c = 'T' then some (.bool true, rest)
      else if c = 'F' then some (.bool false, rest)
      else if c = 'I' then (readInt rest).map (fun p => (Val.int p.1, p.2))
      else if c = 'S' then (readStr rest).map (fun p => (Val.str p.1, p.2))
      else if c = 'L' then
        match readNat rest with
        | some (n, r) =>
            match pList fuel n r with
            | some (xs, r2) => some (Val.list xs, r2)
            | none => none
        | none => none
      else if c = 'O' then
        match readNat rest with
        | some (n, r) =>
            match pFields fuel n r with
            | some (fs, r2) => some (Val.obj fs, r2)
            | none => none
        | none => none
      else none
  termination_by fuel _ => (fuel, 0)

/-- Parsing exactly `n` values. -/
def pList : Nat → Nat → List Char → Option (List Val × List Char)
  | _, 0, s => some ([], s)
  | fuel, n + 1, s =>
      match pVal fuel s with
      | some (v, r) =>
          match pList fuel n r with
          | some (vs, r2) => some (v :: vs, r2)
          | none => none
      | none => none
  termination_by fuel n _ => (fuel, n + 1)

/-- Parsing exactly `n` fields. -/
def pFields : Nat → Nat → List Char → Option (List (List Char × Val) × List Char)
  | _, 0, s => some ([], s)
  | fuel, n + 1, s =>
      match readStr s with
      | some (k, r0) =>
          match pVal fuel r0 with
          | some (v, r) =>
              match pFields fuel n r with
              | some (fs, r2) => some ((k, v) :: fs, r2)
              | none => none
          | none => none
      | none => none
  termination_by fuel n _ => (fuel, n + 1)

end

/-- The round-trip property of one value, with the fuel made explicit. -/
def RoundTrips (v : Val) : Prop :=
  ∀ fuel rest, (canonEnc v).length ≤ fuel → pVal fuel (canonEnc v ++ rest) = some (v, rest)

theorem canonEncList_length_mem {xs : List Val} {v : Val} (h : v ∈ xs) :
    (canonEnc v).length ≤ (canonEncList xs).length := by
  induction xs with
  | nil => simp at h
  | cons a as ih =>
      rcases List.mem_cons.1 h with rfl | h
      · simp [canonEncList]
      · have := ih h
        simp [canonEncList]
        omega

theorem pList_roundTrip (xs : List Val) (h : ∀ v ∈ xs, RoundTrips v) :
    ∀ fuel rest, (canonEncList xs).length ≤ fuel →
      pList fuel xs.length (canonEncList xs ++ rest) = some (xs, rest) := by
  induction xs with
  | nil => intro fuel rest _; simp [pList, canonEncList]
  | cons a as ih =>
      intro fuel rest hlen
      have hlen' : (canonEnc a).length + (canonEncList as).length ≤ fuel := by
        simpa [canonEncList] using hlen
      have hhead := h a (by simp) fuel (canonEncList as ++ rest) (by omega)
      have htail := ih (fun v hv => h v (by simp [hv])) fuel rest (by omega)
      have hcat : canonEncList (a :: as) ++ rest = canonEnc a ++ (canonEncList as ++ rest) := by
        simp [canonEncList]
      rw [hcat]
      simp [pList, hhead, htail]

theorem pFields_roundTrip (fs : List (List Char × Val)) (h : ∀ kv ∈ fs, RoundTrips kv.2) :
    ∀ fuel rest, (canonEncFields fs).length ≤ fuel →
      pFields fuel fs.length (canonEncFields fs ++ rest) = some (fs, rest) := by
  induction fs with
  | nil => intro fuel rest _; simp [pFields, canonEncFields]
  | cons a as ih =>
      intro fuel rest hlen
      have hlen' : (encStr a.1).length + ((canonEnc a.2).length + (canonEncFields as).length) ≤ fuel := by
        simpa [canonEncFields] using hlen
      have hkey := readStr_encStr a.1 (canonEnc a.2 ++ (canonEncFields as ++ rest))
      have hval := h a (by simp) fuel (canonEncFields as ++ rest) (by omega)
      have htail := ih (fun kv hkv => h kv (by simp [hkv])) fuel rest (by omega)
      have hcat : canonEncFields (a :: as) ++ rest
          = encStr a.1 ++ (canonEnc a.2 ++ (canonEncFields as ++ rest)) := by
        simp [canonEncFields]
      rw [hcat]
      simp [pFields, hkey, hval, htail]

/-- **Every value survives the canonical serialization**, with fuel equal
to the length of the text. -/
theorem pVal_canonEnc (v : Val) : RoundTrips v := by
  induction v using Val.strong with
  | hnull => intro fuel rest hlen; cases fuel with
      | zero => simp [canonEnc] at hlen
      | succ f => simp [canonEnc, pVal]
  | hbool b => intro fuel rest hlen; cases fuel with
      | zero => cases b <;> simp [canonEnc] at hlen
      | succ f => cases b <;> simp [canonEnc, pVal]
  | hint n => intro fuel rest hlen; cases fuel with
      | zero => simp [canonEnc, encInt] at hlen
      | succ f => simpa [canonEnc, pVal] using readInt_encInt n rest
  | hstr s => intro fuel rest hlen; cases fuel with
      | zero => simp [canonEnc, encStr] at hlen
      | succ f => simpa [canonEnc, pVal] using readStr_encStr s rest
  | hlist xs hxs =>
      intro fuel rest hlen
      cases fuel with
      | zero => simp [canonEnc] at hlen
      | succ f =>
          have hf : (natDigits xs.length).length + 1 + (canonEncList xs).length ≤ f := by
            simp [canonEnc] at hlen; omega
          have hkey := readNat_natDigits xs.length (canonEncList xs ++ rest)
          have hbody := pList_roundTrip xs hxs f rest (by omega)
          have hcat : canonEnc (Val.list xs) ++ rest
              = 'L' :: (natDigits xs.length ++ ';' :: (canonEncList xs ++ rest)) := by
            simp [canonEnc]
          rw [hcat]
          simp [pVal, hkey, hbody]
  | hobj fs hfs =>
      intro fuel rest hlen
      cases fuel with
      | zero => simp [canonEnc] at hlen
      | succ f =>
          have hf : (natDigits fs.length).length + 1 + (canonEncFields fs).length ≤ f := by
            simp [canonEnc] at hlen; omega
          have hkey := readNat_natDigits fs.length (canonEncFields fs ++ rest)
          have hbody := pFields_roundTrip fs hfs f rest (by omega)
          have hcat : canonEnc (Val.obj fs) ++ rest
              = 'O' :: (natDigits fs.length ++ ';' :: (canonEncFields fs ++ rest)) := by
            simp [canonEnc]
          rw [hcat]
          simp [pVal, hkey, hbody]

/-- The canonical decoder: parse one value and insist that the text is
completely consumed. -/
def canonDecode (s : List Char) : Option Val :=
  match pVal s.length s with
  | some (v, []) => some v
  | _ => none

/-- **The canonical round trip.** -/
theorem canonDecode_canonEnc (v : Val) : canonDecode (canonEnc v) = some v := by
  have h := pVal_canonEnc v (canonEnc v).length [] (by simp)
  simp only [List.append_nil] at h
  simp [canonDecode, h]

/-- **The canonical serialization is injective**: distinct values never
serialize to the same text, so a hash of it is a content identity. -/
theorem canonEnc_injective {a b : Val} (h : canonEnc a = canonEnc b) : a = b := by
  have ha := canonDecode_canonEnc a
  rw [h, canonDecode_canonEnc b] at ha
  exact (Option.some.inj ha).symm

/-! ## Content identity -/

/-- The bytes of a piece of canonical text (four bytes per character, so
that the map is injective on all of Unicode). -/
def charBytes (c : Char) : Blob :=
  [UInt8.ofNat (c.toNat / 16777216 % 256), UInt8.ofNat (c.toNat / 65536 % 256),
   UInt8.ofNat (c.toNat / 256 % 256), UInt8.ofNat (c.toNat % 256)]

/-- The bytes of a canonical serialization. -/
def canonBytes (v : Val) : Blob := (canonEnc v).flatMap charBytes

/-- The content identity of a value: the witness of its canonical bytes. -/
def valHash (v : Val) : List Char := witness (canonBytes v)

theorem valHash_length (v : Val) : (valHash v).length = 64 := by
  simp [valHash]

/-- Equal values have equal content identity. -/
theorem valHash_eq_of_eq {a b : Val} (h : a = b) : valHash a = valHash b := by rw [h]

/-- Different hashes mean different values. -/
theorem ne_of_valHash_ne {a b : Val} (h : valHash a ≠ valHash b) : a ≠ b := by
  intro hab; exact h (valHash_eq_of_eq hab)

end Kant.Codec
