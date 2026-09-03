/-
# Compressed code movies: snippets, Gödel numbers and circuits

A "code movie" is a looped sequence of short code frames — the demo-scene
style playback the pastebin uses for its snippet galleries.  A movie has
to survive three representations:

* **compressed** (run-length encoded frames), for storage and transport;
* a single **Gödel number**, so a whole movie can travel as one integer
  in a URL fragment, a QR code or a stego payload;
* a **circuit**, when the frame is a combinational netlist rather than
  text.

Proved here:

* `rleDecode_rleEncode` — compression is lossless, and `rleEncode_length`
  bounds the compressed size;
* `ungodel_godel`, `godel_injective` — the Gödel numbering of a frame is
  a genuine bijection onto its image, so a movie can be recovered from
  its number;
* `unmovie_movieGodel` — the same for a whole movie (a list of frames);
* `parse_tokens` / `decodeCircuit_encodeCircuit` — a circuit round-trips
  through its postfix token stream, hence through a Gödel number;
* `frameAt_periodic` — playback loops with the movie's own period.
-/
import Mathlib

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.CodeMovie

/-- One frame of a code movie: a short snippet of byte codes. -/
abbrev Snippet := List Nat

/-- A code movie: a sequence of frames, played in a loop. -/
abbrev Movie := List Snippet

/-! ## Run-length compression -/

/-- Run-length encode a snippet as `(value, count)` pairs. -/
def rleEncode : Snippet → List (Nat × Nat)
  | [] => []
  | x :: xs =>
      match rleEncode xs with
      | [] => [(x, 1)]
      | (y, n) :: rest => if x = y then (y, n + 1) :: rest else (x, 1) :: (y, n) :: rest

/-- Expand a run-length encoding. -/
def rleDecode (l : List (Nat × Nat)) : Snippet :=
  l.flatMap (fun p => List.replicate p.2 p.1)

/-- **Compression is lossless.** -/
theorem rleDecode_rleEncode (s : Snippet) : rleDecode (rleEncode s) = s := by
  induction s with
  | nil => rfl
  | cons x xs ih =>
      rw [rleEncode]
      cases h : rleEncode xs with
      | nil =>
          rw [h] at ih
          simp only [rleDecode, List.flatMap_nil] at ih
          simp [rleDecode, ← ih]
      | cons p rest =>
          obtain ⟨y, n⟩ := p
          rw [h] at ih
          by_cases hxy : x = y
          · subst hxy
            simp only [if_true, rleDecode, List.flatMap_cons] at ih ⊢
            rw [List.replicate_succ, List.cons_append, ih]
          · simp only [if_neg hxy, rleDecode, List.flatMap_cons] at ih ⊢
            rw [← ih]
            simp

/-- The compressed form is never longer than twice the number of runs. -/
theorem rleEncode_length (s : Snippet) : (rleEncode s).length ≤ s.length := by
  induction s with
  | nil => simp [rleEncode]
  | cons x xs ih =>
      rw [rleEncode]
      cases h : rleEncode xs with
      | nil => simp
      | cons p rest =>
          obtain ⟨y, n⟩ := p
          rw [h] at ih
          by_cases hxy : x = y
          · subst hxy
            simp only [if_true, List.length_cons] at ih ⊢
            omega
          · simp only [if_neg hxy, List.length_cons] at ih ⊢
            omega

/-! ## Gödel numbering of a frame -/

/-- The Gödel number of a snippet: an injective encoding of a list of
naturals into one natural, via Cantor pairing. -/
def godel : Snippet → Nat
  | [] => 0
  | a :: l => Nat.pair a (godel l) + 1

/-- Decode a Gödel number back into a snippet. -/
def ungodel : Nat → Snippet
  | 0 => []
  | n + 1 => (Nat.unpair n).1 :: ungodel (Nat.unpair n).2
  termination_by n => n
  decreasing_by
    have h := Nat.unpair_right_le n
    omega

/-- **A snippet is recoverable from its Gödel number.** -/
@[simp] theorem ungodel_godel (s : Snippet) : ungodel (godel s) = s := by
  induction s with
  | nil => simp [godel, ungodel]
  | cons a l ih =>
      rw [godel, ungodel, Nat.unpair_pair, ih]

/-- Gödel numbering is injective. -/
theorem godel_injective : Function.Injective godel := by
  intro a b h
  have := congrArg ungodel h
  rwa [ungodel_godel, ungodel_godel] at this

/-! ## Gödel numbering of a whole movie -/

/-- The Gödel number of a movie: fold the frames' numbers. -/
def movieGodel (m : Movie) : Nat := godel (m.map godel)

/-- Recover a movie from its number. -/
def unmovie (n : Nat) : Movie := (ungodel n).map ungodel

/-- **A whole movie is recoverable from a single integer**, so it can
travel in a URL fragment, a QR code or a stego payload. -/
theorem unmovie_movieGodel (m : Movie) : unmovie (movieGodel m) = m := by
  unfold unmovie movieGodel
  rw [ungodel_godel, List.map_map, Function.comp_def]
  simp

/-! ## Playback -/

/-- The frame shown at time `t` of a looping movie. -/
def frameAt (m : Movie) (t : Nat) : Snippet :=
  if h : m.length = 0 then [] else m[t % m.length]'(by
    have : 0 < m.length := Nat.pos_of_ne_zero h
    exact Nat.mod_lt _ this)

/-- Playback loops with the movie's own period. -/
theorem frameAt_periodic (m : Movie) (t : Nat) : frameAt m (t + m.length) = frameAt m t := by
  unfold frameAt
  by_cases h : m.length = 0
  · simp [h]
  · simp only [dif_neg h, Nat.add_mod_right]

/-! ## Circuits as frames -/

/-- A combinational circuit frame. -/
inductive Circuit
  | inp (i : Nat)
  | const (b : Bool)
  | not (c : Circuit)
  | and (c₁ c₂ : Circuit)
  | or (c₁ c₂ : Circuit)
deriving DecidableEq, Repr

namespace Circuit

/-- Evaluate a circuit against an input assignment. -/
def eval (env : Nat → Bool) : Circuit → Bool
  | .inp i => env i
  | .const b => b
  | .not c => !(eval env c)
  | .and c₁ c₂ => (eval env c₁) && (eval env c₂)
  | .or c₁ c₂ => (eval env c₁) || (eval env c₂)

/-- Postfix token stream of a circuit. -/
def tokens : Circuit → List Nat
  | .inp i => [0, i]
  | .const b => [1, if b then 1 else 0]
  | .not c => tokens c ++ [2]
  | .and c₁ c₂ => tokens c₁ ++ tokens c₂ ++ [3]
  | .or c₁ c₂ => tokens c₁ ++ tokens c₂ ++ [4]

/-- Stack machine that rebuilds a circuit from its token stream. -/
def run : List Nat → List Circuit → Option (List Circuit)
  | [], st => some st
  | 0 :: i :: rest, st => run rest (Circuit.inp i :: st)
  | 1 :: b :: rest, st => run rest (Circuit.const (b == 1) :: st)
  | 2 :: rest, c :: st => run rest (Circuit.not c :: st)
  | 3 :: rest, c₂ :: c₁ :: st => run rest (Circuit.and c₁ c₂ :: st)
  | 4 :: rest, c₂ :: c₁ :: st => run rest (Circuit.or c₁ c₂ :: st)
  | _, _ => none

/-- Running the tokens of a circuit pushes exactly that circuit. -/
theorem parse_tokens (c : Circuit) (rest : List Nat) (st : List Circuit) :
    run (tokens c ++ rest) st = run rest (c :: st) := by
  induction c generalizing rest st with
  | inp i => rfl
  | const b => cases b <;> rfl
  | not c ih =>
      simp only [tokens, List.append_assoc, List.cons_append, List.nil_append, ih, run]
  | and c₁ c₂ ih₁ ih₂ =>
      simp only [tokens, List.append_assoc, List.cons_append, List.nil_append, ih₁, ih₂, run]
  | or c₁ c₂ ih₁ ih₂ =>
      simp only [tokens, List.append_assoc, List.cons_append, List.nil_append, ih₁, ih₂, run]

/-- Encode a circuit as a Gödel number. -/
def encode (c : Circuit) : Nat := godel (tokens c)

/-- Decode a Gödel number back into a circuit. -/
def decode (n : Nat) : Option Circuit :=
  match run (ungodel n) [] with
  | some [c] => some c
  | _ => none

/-- **A circuit survives the trip through a single integer.** -/
theorem decodeCircuit_encodeCircuit (c : Circuit) : decode (encode c) = some c := by
  unfold decode encode
  rw [ungodel_godel]
  have h : run (tokens c) [] = some [c] := by
    have := parse_tokens c [] []
    simpa using this
  rw [h]

/-- Distinct circuits get distinct Gödel numbers. -/
theorem encode_injective : Function.Injective encode := by
  intro a b h
  have h' := congrArg decode h
  rw [decodeCircuit_encodeCircuit, decodeCircuit_encodeCircuit] at h'
  exact Option.some.inj h'

end Circuit

end Kant.CodeMovie
