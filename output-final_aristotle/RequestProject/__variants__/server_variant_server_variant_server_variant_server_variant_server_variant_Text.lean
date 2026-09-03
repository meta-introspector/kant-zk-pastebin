/-
# Text utilities: ASCII transcoding, field framing and substring search

The reader-facing layers of the pastebin — the *feed* of posts
(`Kant.Feed`), the copy/paste envelope (`Kant.Clipboard`) and the meme
exporter (`Kant.Meme`) — all need to move between bytes and characters,
to frame several byte strings into one flat string, and to search a post
for a phrase.  Those three utilities live here so the layers above can
share them.

Proved here:

* `asciiChars_asciiBytes` / `asciiBytes_asciiChars` — transcoding between
  ASCII text and bytes round-trips in both directions;
* `splitFields_joinFields` — a list of separator-free fields survives
  being flattened into one string and split again, which is what makes
  the copy/paste envelope unambiguous;
* `containsSub_iff_infix` — the substring test used by feed search is
  exactly the `IsInfix` relation, so search never invents or misses a
  match.
-/
import Mathlib
import RequestProject.Kant.Bytes

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.Text

open Kant.Bytes

/-! ## ASCII transcoding -/

/-- Text that can be transported as one byte per character. -/
def IsAscii (cs : List Char) : Prop := ∀ c ∈ cs, c.toNat < 128

/-- Bytes that decode as ASCII characters. -/
def BytesAscii (bs : Blob) : Prop := ∀ b ∈ bs, b.toNat < 128

/-- ASCII text as bytes. -/
def asciiBytes (cs : List Char) : Blob := cs.map (fun c => UInt8.ofNat c.toNat)

/-- Bytes read back as text. -/
def asciiChars (bs : Blob) : List Char := bs.map (fun b => Char.ofNat b.toNat)

@[simp] theorem asciiBytes_length (cs : List Char) : (asciiBytes cs).length = cs.length := by
  simp [asciiBytes]

@[simp] theorem asciiChars_length (bs : Blob) : (asciiChars bs).length = bs.length := by
  simp [asciiChars]

@[simp] theorem asciiBytes_nil : asciiBytes [] = [] := rfl

@[simp] theorem asciiBytes_cons (c : Char) (cs : List Char) :
    asciiBytes (c :: cs) = UInt8.ofNat c.toNat :: asciiBytes cs := rfl

@[simp] theorem asciiBytes_append (a b : List Char) :
    asciiBytes (a ++ b) = asciiBytes a ++ asciiBytes b := by
  simp [asciiBytes]

/-- ASCII text survives a trip through bytes. -/
theorem asciiChars_asciiBytes {cs : List Char} (h : IsAscii cs) :
    asciiChars (asciiBytes cs) = cs := by
  induction cs with
  | nil => rfl
  | cons c cs ih =>
      have hc : c.toNat < 128 := h c (by simp)
      have hrest : IsAscii cs := fun x hx => h x (by simp [hx])
      have hb : (UInt8.ofNat c.toNat).toNat = c.toNat := by simp; omega
      simpa [asciiChars, asciiBytes, hb, Char.ofNat_toNat] using ih hrest

/-- ASCII bytes survive a trip through text. -/
theorem asciiBytes_asciiChars {bs : Blob} (h : BytesAscii bs) :
    asciiBytes (asciiChars bs) = bs := by
  induction bs with
  | nil => rfl
  | cons b bs ih =>
      have hb : b.toNat < 128 := h b (by simp)
      have hrest : BytesAscii bs := fun x hx => h x (by simp [hx])
      have hvalid : (Char.ofNat b.toNat).toNat = b.toNat := by
        rw [Char.toNat_ofNat, if_pos (Or.inl (by omega))]
      have hb' : UInt8.ofNat (Char.ofNat b.toNat).toNat = b := by
        rw [hvalid]
        simp
      simpa [asciiBytes, asciiChars, hb'] using ih hrest

/-- Every byte produced from ASCII text is itself an ASCII byte. -/
theorem bytesAscii_asciiBytes {cs : List Char} (h : IsAscii cs) : BytesAscii (asciiBytes cs) := by
  intro b hb
  simp only [asciiBytes, List.mem_map] at hb
  obtain ⟨c, hc, rfl⟩ := hb
  have := h c hc
  have hb : (UInt8.ofNat c.toNat).toNat = c.toNat := by simp; omega
  omega

/-! ### Character codes

The steganographic carrier of `Kant.Stego` stores plain natural numbers,
one per image sample, so text destined for a carrier is transcoded to
code points rather than to `UInt8`. -/

/-- Text as a list of character codes. -/
def charCodes (cs : List Char) : List Nat := cs.map Char.toNat

/-- Character codes read back as text. -/
def codeChars (ns : List Nat) : List Char := ns.map Char.ofNat

@[simp] theorem charCodes_length (cs : List Char) : (charCodes cs).length = cs.length := by
  simp [charCodes]

@[simp] theorem charCodes_append (a b : List Char) :
    charCodes (a ++ b) = charCodes a ++ charCodes b := by
  simp [charCodes]

/-- Text survives a trip through character codes. -/
theorem codeChars_charCodes (cs : List Char) : codeChars (charCodes cs) = cs := by
  simp [codeChars, charCodes, List.map_map, Function.comp_def, Char.ofNat_toNat]

/-- ASCII codes are bytes. -/
theorem charCodes_lt_256 {cs : List Char} (h : IsAscii cs) : ∀ v ∈ charCodes cs, v < 256 := by
  intro v hv
  simp only [charCodes, List.mem_map] at hv
  obtain ⟨c, hc, rfl⟩ := hv
  have := h c hc
  omega

/-- Codes of non-NUL characters are non-zero. -/
theorem charCodes_ne_zero {cs : List Char} (h : ∀ c ∈ cs, 0 < c.toNat) :
    ∀ v ∈ charCodes cs, v ≠ 0 := by
  intro v hv
  simp only [charCodes, List.mem_map] at hv
  obtain ⟨c, hc, rfl⟩ := hv
  have := h c hc
  omega

/-- Hex strings are ASCII. -/
theorem isAscii_hexEncode (bs : Blob) : IsAscii (hexEncode bs) := by
  intro c hc
  simp only [hexEncode, List.mem_flatMap] at hc
  obtain ⟨b, _, hcb⟩ := hc
  have hb : b.toNat < 256 := b.toNat_lt_size
  have h1 : b.toNat / 16 < 16 := by omega
  have h2 : b.toNat % 16 < 16 := Nat.mod_lt _ (by norm_num)
  have hdig : ∀ n, n < 16 → (hexDigit n).toNat < 128 := by
    intro n hn; interval_cases n <;> decide
  simp only [hexByte, List.mem_cons, List.not_mem_nil, or_false] at hcb
  rcases hcb with rfl | rfl
  · exact hdig _ h1
  · exact hdig _ h2

/-! ## Field framing

Byte fields are hex encoded and then joined with `':'`.  Hex never
produces a colon, so splitting recovers the fields exactly. -/

/-- The field separator. -/
def sep : Char := ':'

/-- Flatten fields into one string, separated by `':'`. -/
def joinFields : List (List Char) → List Char
  | [] => []
  | [f] => f
  | f :: fs => f ++ sep :: joinFields fs

/-- Split a string at every `':'`.  Always returns at least one field. -/
def splitFields : List Char → List (List Char)
  | [] => [[]]
  | c :: cs =>
      if c = sep then [] :: splitFields cs
      else
        match splitFields cs with
        | [] => [[c]]
        | f :: fs => (c :: f) :: fs

theorem splitFields_ne_nil (s : List Char) : splitFields s ≠ [] := by
  induction s with
  | nil => simp [splitFields]
  | cons c cs ih =>
      unfold splitFields
      split
      · simp
      · split <;> simp

/-- A separator-free string is a single field. -/
theorem splitFields_of_no_sep {f : List Char} (h : sep ∉ f) : splitFields f = [f] := by
  induction f with
  | nil => rfl
  | cons c cs ih =>
      have hc : c ≠ sep := fun hc => h (by simp [hc])
      have hrest : sep ∉ cs := fun hx => h (by simp [hx])
      rw [splitFields, if_neg hc, ih hrest]

/-- Splitting peels off one separator-free field at a time. -/
theorem splitFields_append {f rest : List Char} (h : sep ∉ f) :
    splitFields (f ++ sep :: rest) = f :: splitFields rest := by
  induction f with
  | nil => simp [splitFields]
  | cons c cs ih =>
      have hc : c ≠ sep := fun hc => h (by simp [hc])
      have hrest : sep ∉ cs := fun hx => h (by simp [hx])
      rw [List.cons_append, splitFields, if_neg hc, ih hrest]

/-- **Framing is unambiguous.**  Any non-empty list of separator-free
fields comes back exactly as it was sent. -/
theorem splitFields_joinFields {fs : List (List Char)} (hne : fs ≠ [])
    (h : ∀ f ∈ fs, sep ∉ f) : splitFields (joinFields fs) = fs := by
  induction fs with
  | nil => exact absurd rfl hne
  | cons f fs ih =>
      cases fs with
      | nil => exact splitFields_of_no_sep (h f (by simp))
      | cons g gs =>
          have hf : sep ∉ f := h f (by simp)
          have hrest : ∀ x ∈ g :: gs, sep ∉ x := fun x hx => h x (by simp [hx])
          rw [show joinFields (f :: g :: gs) = f ++ sep :: joinFields (g :: gs) from rfl,
            splitFields_append hf, ih (by simp) hrest]

/-- Hex-encoded fields never contain the separator. -/
theorem sep_not_mem_hexEncode (bs : Blob) : sep ∉ hexEncode bs := by
  intro hmem
  simp only [hexEncode, List.mem_flatMap] at hmem
  obtain ⟨b, _, hcb⟩ := hmem
  have hb : b.toNat < 256 := b.toNat_lt_size
  have h1 : b.toNat / 16 < 16 := by omega
  have h2 : b.toNat % 16 < 16 := Nat.mod_lt _ (by norm_num)
  have hdig : ∀ n, n < 16 → hexDigit n ≠ sep := by
    intro n hn; interval_cases n <;> decide
  simp only [hexByte, List.mem_cons, List.not_mem_nil, or_false] at hcb
  rcases hcb with hcb | hcb
  · exact hdig _ h1 hcb.symm
  · exact hdig _ h2 hcb.symm

/-- The separator itself is ASCII. -/
theorem isAscii_sep : sep.toNat < 128 := by decide

/-- Joining ASCII fields yields ASCII text. -/
theorem isAscii_joinFields {fs : List (List Char)} (h : ∀ f ∈ fs, IsAscii f) :
    IsAscii (joinFields fs) := by
  induction fs with
  | nil => intro c hc; simp [joinFields] at hc
  | cons f fs ih =>
      cases fs with
      | nil => exact h f (by simp)
      | cons g gs =>
          intro c hc
          rw [show joinFields (f :: g :: gs) = f ++ sep :: joinFields (g :: gs) from rfl] at hc
          simp only [List.mem_append, List.mem_cons] at hc
          rcases hc with hc | rfl | hc
          · exact h f (by simp) c hc
          · exact isAscii_sep
          · exact ih (fun x hx => h x (by simp [hx])) c hc

/-- Hex digits are never the NUL character; the meme exporter relies on
this to terminate an embedded payload with a zero byte. -/
theorem hexEncode_pos (bs : Blob) : ∀ c ∈ hexEncode bs, 0 < c.toNat := by
  intro c hc
  simp only [hexEncode, List.mem_flatMap] at hc
  obtain ⟨b, _, hcb⟩ := hc
  have hb : b.toNat < 256 := b.toNat_lt_size
  have h1 : b.toNat / 16 < 16 := by omega
  have h2 : b.toNat % 16 < 16 := Nat.mod_lt _ (by norm_num)
  have hdig : ∀ n, n < 16 → 0 < (hexDigit n).toNat := by
    intro n hn; interval_cases n <;> decide
  simp only [hexByte, List.mem_cons, List.not_mem_nil, or_false] at hcb
  rcases hcb with rfl | rfl
  · exact hdig _ h1
  · exact hdig _ h2

/-- Joining fields of non-NUL characters keeps every character non-NUL. -/
theorem joinFields_pos {fs : List (List Char)} (h : ∀ f ∈ fs, ∀ c ∈ f, 0 < c.toNat) :
    ∀ c ∈ joinFields fs, 0 < c.toNat := by
  induction fs with
  | nil => intro c hc; simp [joinFields] at hc
  | cons f fs ih =>
      cases fs with
      | nil => exact h f (by simp)
      | cons g gs =>
          intro c hc
          rw [show joinFields (f :: g :: gs) = f ++ sep :: joinFields (g :: gs) from rfl] at hc
          simp only [List.mem_append, List.mem_cons] at hc
          rcases hc with hc | rfl | hc
          · exact h f (by simp) c hc
          · decide
          · exact ih (fun x hx => h x (by simp [hx])) c hc

/-! ## Substring search -/

/-- Does `hay` contain `needle` as a contiguous block? -/
def containsSub (needle hay : List Char) : Bool :=
  if needle.isPrefixOf hay then true
  else match hay with
    | [] => false
    | _ :: t => containsSub needle t

/-- Search is exactly the infix relation: no phantom hits, no misses. -/
theorem containsSub_iff_infix (needle hay : List Char) :
    containsSub needle hay = true ↔ needle <:+: hay := by
  induction hay with
  | nil =>
      rw [containsSub]
      by_cases h : needle.isPrefixOf ([] : List Char) = true
      · simp only [h, if_true, true_iff]
        exact (List.isPrefixOf_iff_prefix.mp h).isInfix
      · simp only [h, Bool.false_eq_true, if_false, false_iff]
        intro hi
        exact h (List.isPrefixOf_iff_prefix.mpr (List.eq_nil_of_infix_nil hi ▸ List.nil_prefix))
  | cons c t ih =>
      rw [containsSub]
      by_cases h : needle.isPrefixOf (c :: t) = true
      · simp only [h, if_true, true_iff]
        exact (List.isPrefixOf_iff_prefix.mp h).isInfix
      · simp only [h, Bool.false_eq_true, if_false, ih]
        constructor
        · exact List.infix_cons
        · intro hi
          rcases List.infix_cons_iff.mp hi with hp | hs
          · exact absurd (List.isPrefixOf_iff_prefix.mpr hp) h
          · exact hs

/-! ## Canonical byte encoding of numbers

Numeric results (an address, a byte count, a credit balance) travel as
minimal big-endian byte strings. -/

/-- Minimal big-endian byte string of a natural number (`0 ↦ []`). -/
def natToBytesBE (n : Nat) : Blob :=
  if n = 0 then [] else natToBytesBE (n / 256) ++ [UInt8.ofNat (n % 256)]
  termination_by n
  decreasing_by
    rename_i h
    exact Nat.div_lt_self (Nat.pos_of_ne_zero h) (by norm_num)

/-- Value of a big-endian byte string. -/
def bytesBEToNat (bs : Blob) : Nat := bs.foldl (fun acc b => acc * 256 + b.toNat) 0

/-- Numbers survive the byte encoding. -/
theorem bytesBEToNat_natToBytesBE (n : Nat) : bytesBEToNat (natToBytesBE n) = n := by
  induction n using Nat.strong_induction_on with
  | _ n ih =>
      rw [natToBytesBE]
      by_cases h : n = 0
      · simp [h, bytesBEToNat]
      · rw [if_neg h]
        have hlt : n / 256 < n := Nat.div_lt_self (Nat.pos_of_ne_zero h) (by norm_num)
        have hmod : (UInt8.ofNat (n % 256)).toNat = n % 256 := by
          have hlt256 : n % 256 < 256 := Nat.mod_lt _ (by norm_num)
          simp
        unfold bytesBEToNat at ih ⊢
        rw [List.foldl_append]
        simp only [List.foldl_cons, List.foldl_nil, ih _ hlt, hmod]
        omega

/-! ## Decimal value of a timestamp

Feed ordering uses a numeric key extracted from the timestamp string;
non-digit characters are ignored. -/

/-- The numeric value of the decimal digits occurring in a string. -/
def digitsValue (cs : List Char) : Nat :=
  cs.foldl (fun acc c => if '0' ≤ c ∧ c ≤ '9' then acc * 10 + (c.toNat - 48) else acc) 0

end Kant.Text
