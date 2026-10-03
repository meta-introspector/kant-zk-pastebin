/-
# Escaped RDFa — Lean 4 port of the escaping layer of `src/paste.rs`

`escape_html` / `unescape_html` are the foundation of the *escaped RDFa*
("eRDFa") payloads: a paste is rendered into HTML with its content
escaped, and a reader must be able to recover the content character for
character.

Upstream this is four sequential `String::replace` calls in each
direction.  Here escaping is a single character-wise expansion and
unescaping a single-pass decoder, and the essential guarantee is proved:

* `unescape (escape s) = s` for **every** input `s` (`escape_unescape_id`),
  so no paste content is ever corrupted by a round trip through eRDFa;
* escaping is injective, and its output contains no raw markup character
  (`escape_no_markup`), so embedding a paste in HTML cannot break out of
  its element.
-/
import Mathlib

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.Erdfa

/-- Expansion of a single character, as in `escape_html`. -/
def escapeChar (c : Char) : List Char :=
  if c = '&' then ['&', 'a', 'm', 'p', ';']
  else if c = '<' then ['&', 'l', 't', ';']
  else if c = '>' then ['&', 'g', 't', ';']
  else if c = '"' then ['&', 'q', 'u', 'o', 't', ';']
  else [c]

/-- `escape_html`. -/
def escape (s : List Char) : List Char := s.flatMap escapeChar

/-- `unescape_html`, as a single-pass decoder. -/
def unescape : List Char → List Char
  | [] => []
  | '&' :: cs =>
      if ['a', 'm', 'p', ';'].isPrefixOf cs then '&' :: unescape (cs.drop 4)
      else if ['l', 't', ';'].isPrefixOf cs then '<' :: unescape (cs.drop 3)
      else if ['g', 't', ';'].isPrefixOf cs then '>' :: unescape (cs.drop 3)
      else if ['q', 'u', 'o', 't', ';'].isPrefixOf cs then '"' :: unescape (cs.drop 5)
      else '&' :: unescape cs
  | c :: cs => c :: unescape cs
  termination_by l => l.length
  decreasing_by all_goals (simp_wf; try omega)

@[simp] theorem escape_nil : escape [] = [] := rfl

@[simp] theorem escape_cons (c : Char) (s : List Char) :
    escape (c :: s) = escapeChar c ++ escape s := by
  simp [escape]

/-- The upstream test vectors of `test_escape_html` and
`test_unescape_html`. -/
example : escape "<div>".toList = "&lt;div&gt;".toList := by native_decide
example : escape "\"test\"".toList = "&quot;test&quot;".toList := by native_decide
example : unescape "&lt;div&gt;".toList = "<div>".toList := by native_decide
example : unescape "&quot;test&quot;".toList = "\"test\"".toList := by native_decide

/-- Decoding an escaped character followed by arbitrary text peels off
exactly that character. -/
theorem unescape_escapeChar_append (c : Char) (rest : List Char) :
    unescape (escapeChar c ++ rest) = c :: unescape rest := by
  unfold escapeChar
  split_ifs with h1 h2 h3 h4
  · subst h1; simp [unescape]
  · subst h2; simp [unescape]
  · subst h3; simp [unescape]
  · subst h4; simp [unescape]
  · have hc : unescape (c :: rest) = c :: unescape rest := by
      match c, h1 with
      | '&', h => exact absurd rfl h
      | c, _ => simp [unescape]
    simpa using hc

/-- **Round trip.** Escaping then unescaping restores any content. -/
theorem escape_unescape_id (s : List Char) : unescape (escape s) = s := by
  induction s with
  | nil => rw [escape_nil]; simp [unescape]
  | cons c s ih => rw [escape_cons, unescape_escapeChar_append, ih]

/-- Escaping is injective: distinct contents give distinct eRDFa bodies. -/
theorem escape_injective : Function.Injective escape := by
  intro a b h
  have h' := congrArg unescape h
  rwa [escape_unescape_id, escape_unescape_id] at h'

/-- A single escaped character never contains raw markup. -/
theorem escapeChar_no_markup (c : Char) :
    '<' ∉ escapeChar c ∧ '>' ∉ escapeChar c ∧ '"' ∉ escapeChar c := by
  unfold escapeChar
  split_ifs with h1 h2 h3 h4
  · exact ⟨by decide, by decide, by decide⟩
  · exact ⟨by decide, by decide, by decide⟩
  · exact ⟨by decide, by decide, by decide⟩
  · exact ⟨by decide, by decide, by decide⟩
  · simp only [List.mem_singleton]
    exact ⟨fun h => h2 h.symm, fun h => h3 h.symm, fun h => h4 h.symm⟩

/-- The escaped form contains no character that could close or open an
HTML element, nor a quote that could escape an attribute. -/
theorem escape_no_markup (s : List Char) :
    '<' ∉ escape s ∧ '>' ∉ escape s ∧ '"' ∉ escape s := by
  induction s with
  | nil => simp [escape]
  | cons c s ih =>
      obtain ⟨i1, i2, i3⟩ := ih
      obtain ⟨e1, e2, e3⟩ := escapeChar_no_markup c
      rw [escape_cons]
      refine ⟨?_, ?_, ?_⟩ <;> simp only [List.mem_append, not_or]
      exacts [⟨e1, i1⟩, ⟨e2, i2⟩, ⟨e3, i3⟩]

end Kant.Erdfa
