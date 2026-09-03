/-
# The raw-text codec, and format detection

Raw text is a first-class input format: compiler output, a proof sketch,
a stack trace, Lean source, a log.  The system must not assume that
unstructured text is meaningless, and extraction must never destroy the
original.

Proved here:

* `rawDoc_text` — the raw document keeps the original text, character for
  character, whatever else is extracted from it;
* `joinLines_splitLines` — the extracted lines put the text back
  together exactly, so line extraction is lossless;
* `detect_*` — format detection follows the order the standard
  prescribes: an explicitly declared format wins (`detect_declared`),
  then signatures (`detect_ipdlText`, `detect_csvEncode`), then syntax
  (`detect_xmlEnc`, `detect_canonEnc`, `detect_yamlEnc`), and raw text is
  the fallback that never fails;
* `importAny_status_ne_invalid` — **a failed parser does not mean invalid
  data**: text no codec recognises is imported as `UNKNOWN`, never as
  `INVALID`, and `importAny_sourceData` shows the original bytes are kept.
-/
import Mathlib
import RequestProject.Kant.Codec.Model
import RequestProject.Kant.Codec.Yaml
import RequestProject.Kant.Codec.Xml
import RequestProject.Kant.Codec.Csv
import RequestProject.Kant.Codec.Ipdl

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.Codec

/-! ## Lines -/

/-- Cutting text into lines. -/
def splitLines : List Char → List (List Char)
  | [] => [[]]
  | c :: cs =>
      if c = '\n' then [] :: splitLines cs
      else match splitLines cs with
        | [] => [[c]]
        | l :: ls => (c :: l) :: ls

/-- Putting the lines back together. -/
def joinLines : List (List Char) → List Char
  | [] => []
  | [l] => l
  | l :: ls => l ++ '\n' :: joinLines ls

theorem splitLines_ne_nil (s : List Char) : splitLines s ≠ [] := by
  induction s with
  | nil => simp [splitLines]
  | cons c cs ih =>
      by_cases h : c = '\n'
      · simp [splitLines, h]
      · cases hs : splitLines cs with
        | nil => exact absurd hs ih
        | cons l ls => simp [splitLines, h, hs]

/-- **Line extraction is lossless.** -/
theorem joinLines_splitLines (s : List Char) : joinLines (splitLines s) = s := by
  induction s with
  | nil => rfl
  | cons c cs ih =>
      by_cases h : c = '\n'
      · subst h
        cases hs : splitLines cs with
        | nil => exact absurd hs (splitLines_ne_nil cs)
        | cons l ls =>
            rw [hs] at ih
            simp [splitLines, joinLines, hs, ih]
      · cases hs : splitLines cs with
        | nil => exact absurd hs (splitLines_ne_nil cs)
        | cons l ls =>
            rw [hs] at ih
            cases ls with
            | nil => simp [splitLines, joinLines, h, hs] at ih ⊢; exact ih
            | cons m ms => simp [splitLines, joinLines, h, hs] at ih ⊢; exact ih

/-! ## The raw document -/

/-- Something a heuristic found inside a piece of text.  It records where
it was found, so the original text is never replaced by the extract. -/
structure Extract where
  /-- What kind of thing this is thought to be. -/
  kind : List Char
  /-- Where it starts, in characters. -/
  offset : Nat
  /-- How long it is, in characters. -/
  length : Nat
deriving DecidableEq, Repr, Inhabited

/-- A piece of raw text, with whatever was detected in it.  The original
text is a field, not a by-product: nothing here can lose it. -/
structure RawDoc where
  /-- The original text, kept exactly. -/
  text : List Char
  /-- The declared encoding. -/
  encoding : List Char
  /-- The lines, in order. -/
  lines : List (List Char)
  /-- What was detected. -/
  detected : List Extract
  /-- How sure the parser is, in per cent. -/
  confidence : Nat
deriving Repr, Inhabited

/-- Reading a piece of text as a raw document. -/
def rawDoc (encoding : List Char) (s : List Char) : RawDoc :=
  { text := s, encoding := encoding, lines := splitLines s,
    detected := [⟨"line".toList, 0, s.length⟩], confidence := 100 }

/-- **The original text survives**, whatever was extracted. -/
@[simp] theorem rawDoc_text (encoding s : List Char) : (rawDoc encoding s).text = s := rfl

/-- And the extracted lines put it back together. -/
theorem rawDoc_lines_join (encoding s : List Char) :
    joinLines (rawDoc encoding s).lines = s := joinLines_splitLines s

/-! ## Format detection

The order is the one the standard prescribes: a declared format, then a
signature, then syntax, then the raw-text fallback. -/

/-- Which format a piece of text is in. -/
def detect (declared : Option Fmt) (s : List Char) : Fmt :=
  match declared with
  | some f => f
  | none =>
      if (stripPrefix ipdlHeader s).isSome then .ipdl
      else if (stripPrefix csvHeader s).isSome then .csv
      else if (xmlDecode s).isSome then .xml
      else if (canonDecode s).isSome then .canonical
      else if (yamlDecode s).isSome then .yaml
      else .text

/-- **An explicitly declared format wins.** -/
@[simp] theorem detect_declared (f : Fmt) (s : List Char) : detect (some f) s = f := rfl

/-- Raw text is the fallback, and it never fails. -/
theorem detect_text_of_unrecognised {s : List Char}
    (h1 : stripPrefix ipdlHeader s = none) (h2 : stripPrefix csvHeader s = none)
    (h3 : xmlDecode s = none) (h4 : canonDecode s = none) (h5 : yamlDecode s = none) :
    detect none s = .text := by
  simp [detect, h1, h2, h3, h4, h5]

/-- The first character of a canonical serialization. -/
theorem canonEnc_head (v : Val) :
    ∃ c t, canonEnc v = c :: t ∧
      (c = 'Z' ∨ c = 'T' ∨ c = 'F' ∨ c = 'I' ∨ c = 'S' ∨ c = 'L' ∨ c = 'O') := by
  cases v with
  | null => exact ⟨'Z', [], rfl, by tauto⟩
  | bool b =>
      cases b
      · exact ⟨'F', [], rfl, by tauto⟩
      · exact ⟨'T', [], rfl, by tauto⟩
  | int n => exact ⟨'I', encInt n, rfl, by tauto⟩
  | str s => exact ⟨'S', encStr s, rfl, by tauto⟩
  | list xs => exact ⟨'L', natDigits xs.length ++ ';' :: canonEncList xs, rfl, by tauto⟩
  | obj fs => exact ⟨'O', natDigits fs.length ++ ';' :: canonEncFields fs, rfl, by tauto⟩

/-- The first character of a flow-YAML document. -/
theorem yamlEnc_head_char (v : Val) :
    ∃ c t, yamlEnc v = c :: t ∧
      (c = 'n' ∨ c = 't' ∨ c = 'f' ∨ c = '"' ∨ c = '[' ∨ c = '{' ∨ c = '-' ∨
        digitVal c ≠ none) := by
  cases v with
  | null => exact ⟨'n', ['u', 'l', 'l'], rfl, by tauto⟩
  | bool b =>
      cases b
      · exact ⟨'f', ['a', 'l', 's', 'e'], rfl, by tauto⟩
      · exact ⟨'t', ['r', 'u', 'e'], rfl, by tauto⟩
  | int n =>
      obtain ⟨d, ds, hds, hdv⟩ := natDigits_head n.natAbs
      by_cases h : n < 0
      · exact ⟨'-', natDigits n.natAbs, by simp [yamlEnc, encNumY, h], by tauto⟩
      · exact ⟨d, ds, by simp [yamlEnc, encNumY, h, hds], by tauto⟩
  | str s => exact ⟨'"', esc s ++ ['"'], rfl, by tauto⟩
  | list xs => exact ⟨'[', yamlEncList xs ++ [']'], rfl, by tauto⟩
  | obj fs => exact ⟨'{', yamlEncFields fs ++ ['}'], rfl, by tauto⟩

theorem xmlDecode_eq_none_of_head {s : List Char} {c : Char} {t : List Char}
    (hs : s = c :: t) (hc : c ≠ '<') : xmlDecode s = none := by
  have : xVal s.length s = none := by
    cases hf : s.length with
    | zero => simp [xVal]
    | succ f =>
        rw [xVal.eq_def, hs]
        simp [xNull, xTrue, xFalse, xIntOpen, xStrOpen, xListOpen, xObjOpen, stripPrefix,
          Ne.symm hc]
  simp [xmlDecode, this]

theorem canonDecode_eq_none_of_head {s : List Char} {c : Char} {t : List Char}
    (hs : s = c :: t) (h1 : c ≠ 'Z') (h2 : c ≠ 'T') (h3 : c ≠ 'F') (h4 : c ≠ 'I')
    (h5 : c ≠ 'S') (h6 : c ≠ 'L') (h7 : c ≠ 'O') : canonDecode s = none := by
  have : pVal s.length s = none := by
    cases hf : s.length with
    | zero => simp [pVal]
    | succ f =>
        rw [pVal.eq_def, hs]
        simp [h1, h2, h3, h4, h5, h6, h7]
  simp [canonDecode, this]

/-- IPDL is recognised by its signature. -/
theorem detect_ipdlText (i : Ipdl) : detect none (ipdlText i) = .ipdl := by
  simp [detect, ipdlText]

/-- CSV is recognised by its header. -/
theorem detect_csvEncode (v : Val) : detect none (csvEncode v) = .csv := by
  have hshape : csvEncode v
      = 'o' :: ("bject_id,object_type,field,value,value_type,parent_id\n".toList
          ++ rowsText (rowsVal ['r'] [] [] v)) := by
    simp [csvEncode, csvHeader]
  have h1 : stripPrefix ipdlHeader (csvEncode v) = none := by
    rw [hshape, ipdlHeader]
    exact stripPrefix_cons_ne (by decide)
  have h2 : stripPrefix csvHeader (csvEncode v) = some (rowsText (rowsVal ['r'] [] [] v)) := by
    simp [csvEncode]
  simp [detect, h1, h2]

/-- XML is recognised by its syntax. -/
theorem detect_xmlEnc (v : Val) : detect none (xmlEnc v) = .xml := by
  obtain ⟨c, t, hct, _⟩ := xmlEnc_head v
  have h1 : stripPrefix ipdlHeader (xmlEnc v) = none := by
    rw [hct]; simp [ipdlHeader, stripPrefix]
  have h2 : stripPrefix csvHeader (xmlEnc v) = none := by
    rw [hct]; simp [csvHeader, stripPrefix]
  simp [detect, h1, h2, xmlDecode_xmlEnc]

/-- The canonical serialization is recognised by its syntax. -/
theorem detect_canonEnc (v : Val) : detect none (canonEnc v) = .canonical := by
  obtain ⟨c, t, hct, hc⟩ := canonEnc_head v
  have hcne : c ≠ '<' := by rcases hc with rfl | rfl | rfl | rfl | rfl | rfl | rfl <;> decide
  have h1 : stripPrefix ipdlHeader (canonEnc v) = none := by
    rw [hct]
    have : c ≠ 'i' := by rcases hc with rfl | rfl | rfl | rfl | rfl | rfl | rfl <;> decide
    simp [ipdlHeader, stripPrefix, Ne.symm this]
  have h2 : stripPrefix csvHeader (canonEnc v) = none := by
    rw [hct]
    have : c ≠ 'o' := by rcases hc with rfl | rfl | rfl | rfl | rfl | rfl | rfl <;> decide
    simp [csvHeader, stripPrefix, Ne.symm this]
  have h3 : xmlDecode (canonEnc v) = none := xmlDecode_eq_none_of_head hct hcne
  simp [detect, h1, h2, h3, canonDecode_canonEnc]

/-- Flow YAML is recognised by its syntax. -/
theorem detect_yamlEnc (v : Val) : detect none (yamlEnc v) = .yaml := by
  obtain ⟨c, t, hct, hc⟩ := yamlEnc_head_char v
  have hdig : ∀ d : Char, digitVal d ≠ none →
      d ≠ '<' ∧ d ≠ 'i' ∧ d ≠ 'o' ∧ d ≠ 'Z' ∧ d ≠ 'T' ∧ d ≠ 'F' ∧ d ≠ 'I' ∧ d ≠ 'S' ∧
        d ≠ 'L' ∧ d ≠ 'O' := by
    intro d hd
    refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩ <;>
      (rintro rfl; exact hd (by decide))
  have hcne : c ≠ '<' := by
    rcases hc with rfl | rfl | rfl | rfl | rfl | rfl | rfl | hd
    · decide
    · decide
    · decide
    · decide
    · decide
    · decide
    · decide
    · exact (hdig c hd).1
  have h1 : stripPrefix ipdlHeader (yamlEnc v) = none := by
    rw [hct]
    have hci : c ≠ 'i' := by
      rcases hc with rfl | rfl | rfl | rfl | rfl | rfl | rfl | hd
      · decide
      · decide
      · decide
      · decide
      · decide
      · decide
      · decide
      · exact (hdig c hd).2.1
    simp [ipdlHeader, stripPrefix, Ne.symm hci]
  have h2 : stripPrefix csvHeader (yamlEnc v) = none := by
    rw [hct]
    have hco : c ≠ 'o' := by
      rcases hc with rfl | rfl | rfl | rfl | rfl | rfl | rfl | hd
      · decide
      · decide
      · decide
      · decide
      · decide
      · decide
      · decide
      · exact (hdig c hd).2.2.1
    simp [csvHeader, stripPrefix, Ne.symm hco]
  have h3 : xmlDecode (yamlEnc v) = none := xmlDecode_eq_none_of_head hct hcne
  have h4 : canonDecode (yamlEnc v) = none := by
    refine canonDecode_eq_none_of_head hct ?_ ?_ ?_ ?_ ?_ ?_ ?_ <;>
      (rcases hc with rfl | rfl | rfl | rfl | rfl | rfl | rfl | hd
       · decide
       · decide
       · decide
       · decide
       · decide
       · decide
       · decide
       · first
         | exact (hdig c hd).2.2.2.1
         | exact (hdig c hd).2.2.2.2.1
         | exact (hdig c hd).2.2.2.2.2.1
         | exact (hdig c hd).2.2.2.2.2.2.1
         | exact (hdig c hd).2.2.2.2.2.2.2.1
         | exact (hdig c hd).2.2.2.2.2.2.2.2.1
         | exact (hdig c hd).2.2.2.2.2.2.2.2.2)
  simp [detect, h1, h2, h3, h4, yamlDecode_yamlEnc]

/-! ## Importing anything at all -/

/-- The value a piece of text decodes to, in whatever format it turns out
to be in.  `none` means *no codec recognised it*, which is not the same
as *the data is invalid*. -/
def decodeAs : Fmt → List Char → Option Val
  | .canonical, s => canonDecode s
  | .yaml, s => yamlDecode s
  | .xml, s => xmlDecode s
  | .csv, s => csvDecode s
  | .ipdl, s => (ipdlRead s).map project
  | .text, _ => none
  | .unknown, _ => none

/-- Importing a piece of text: keep the original, record the format that
was detected, and fall back to raw text rather than pretending the data
is invalid. -/
def importAny (declared : Option Fmt) (source : List Char) : Obj :=
  match decodeAs (detect declared source) source with
  | some v =>
      match Obj.ofVal v with
      | some o => { o with sourceFormat := detect declared source, sourceData := source }
      | none =>
          { (default : Obj) with
            kind := "value".toList,
            outputs := [{ id := "value".toList, name := "value".toList,
                          type := "canonical".toList, value := v, encoding := [],
                          claims := [], certificate := .null, provenance := none }],
            sourceFormat := detect declared source, sourceData := source, status := .unknown }
  | none =>
      { (default : Obj) with
        kind := "raw".toList,
        inputs := [{ id := "text".toList, name := "text".toList, type := "text".toList,
                     value := .str source, encoding := "utf-8".toList, units := [],
                     constraints := [], provenance := none }],
        sourceFormat := detect declared source, sourceData := source, status := .unknown,
        warnings := [{ id := "w1".toList, code := "UNRECOGNISED_FORMAT".toList,
                       severity := .warning,
                       message := "no codec recognised this text; kept as raw text".toList,
                       location := [], field := [], objectId := [], sourceSystem := [],
                       sourceFormat := detect declared source, expected := [], actual := [],
                       cause := [],
                       resolution := "preserved".toList, recoverable := true }] }

/-- **The original text is always kept.** -/
@[simp] theorem importAny_sourceData (declared : Option Fmt) (s : List Char) :
    (importAny declared s).sourceData = s := by
  unfold importAny
  split
  · split <;> rfl
  · rfl

/-- Text no codec recognises still arrives as a proof object that keeps
the text and says so. -/
theorem importAny_unrecognised {declared : Option Fmt} {s : List Char}
    (h : decodeAs (detect declared s) s = none) :
    (importAny declared s).status = .unknown ∧ (importAny declared s).kind = "raw".toList := by
  unfold importAny
  simp [h]

/-- **A failed parser never means invalid data**: unrecognised text is
`UNKNOWN`, and the warning that says so is `recoverable`. -/
theorem importAny_status_ne_invalid {declared : Option Fmt} {s : List Char}
    (h : decodeAs (detect declared s) s = none) :
    (importAny declared s).status ≠ .invalid := by
  rw [(importAny_unrecognised h).1]
  decide

/-- **A status is never silently converted**: what a codec decoded is
what the object says. -/
theorem importAny_status_of_decoded {declared : Option Fmt} {s : List Char} {v : Val} {o : Obj}
    (hv : decodeAs (detect declared s) s = some v) (ho : Obj.ofVal v = some o) :
    (importAny declared s).status = o.status := by
  unfold importAny
  simp [hv, ho]

end Kant.Codec
