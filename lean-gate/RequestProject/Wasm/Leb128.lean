/-
# LEB128 — the variable-length integer encoding of the WebAssembly binary format

This is a Lean 4 (re)implementation of the LEB128 layer that
`argumentcomputer/Wasm.lean` (`Wasm/Leb128.lean`) provides for its wasm
binary encoder.  That library targets a 2023 Lean nightly and depends on
packages that no longer build against the toolchain used here, so the
algorithm is re-derived directly from the binary-format specification and
—unlike the original— comes with round-trip proofs.

Two encoders are needed by `RequestProject.Wasm.Encode`:

* `uleb` — unsigned LEB128, used for indices, sizes and vector lengths;
* `sleb` — signed LEB128 restricted to non-negative values, used for the
  immediate of `i64.const` (the spec mandates the *signed* encoding there).

Both are proved to round-trip against explicit decoders, which is exactly
the statement "the bytes we emit are read back by a conforming decoder as
the numbers we meant".

This module is deliberately Mathlib-free: it is part of the compute-only
core that is extracted to WebAssembly.
-/

namespace Kant.Wasm.Leb128

/-! ## Unsigned LEB128 -/

/-- Unsigned LEB128 encoding of a natural number: little-endian groups of
seven bits, every non-final byte carrying the continuation bit `0x80`. -/
def uleb (n : Nat) : List UInt8 :=
  if n < 128 then [UInt8.ofNat n]
  else UInt8.ofNat (n % 128 + 128) :: uleb (n / 128)
termination_by n
decreasing_by omega

/-- Unsigned LEB128 decoder: returns the value and the unconsumed bytes. -/
def ulebDec : List UInt8 → Option (Nat × List UInt8)
  | [] => none
  | b :: bs =>
    if b.toNat < 128 then some (b.toNat, bs)
    else match ulebDec bs with
      | some (n, rest) => some (b.toNat - 128 + 128 * n, rest)
      | none => none

theorem toNat_ofNat_lt {n : Nat} (h : n < 256) : (UInt8.ofNat n).toNat = n := by
  simp [Nat.mod_eq_of_lt h]

/-- Unsigned LEB128 round-trips, in a stream: decoding the encoding of `n`
followed by arbitrary further bytes returns `n` and those bytes. -/
theorem ulebDec_uleb (n : Nat) (rest : List UInt8) :
    ulebDec (uleb n ++ rest) = some (n, rest) := by
  induction n using uleb.induct with
  | case1 n h =>
      rw [uleb, if_pos h]
      simp [ulebDec, toNat_ofNat_lt (by omega : n < 256), h]
  | case2 n h ih =>
      rw [uleb, if_neg h]
      have hb : (UInt8.ofNat (n % 128 + 128)).toNat = n % 128 + 128 :=
        toNat_ofNat_lt (by omega)
      simp only [List.cons_append, ulebDec, hb, if_neg (by omega : ¬ n % 128 + 128 < 128), ih]
      have harith : n % 128 + 128 - 128 + 128 * (n / 128) = n := by omega
      rw [harith]

/-- `uleb` never returns the empty byte string. -/
theorem uleb_ne_nil (n : Nat) : uleb n ≠ [] := by
  rw [uleb]; split <;> simp

/-! ## Signed LEB128 (non-negative values) -/

/-- Signed LEB128 encoding of a non-negative number.  It agrees with the
unsigned encoding except that the final group must leave the sign bit
clear, so values in `[64, 128)` need a second byte. -/
def sleb (n : Nat) : List UInt8 :=
  if n < 64 then [UInt8.ofNat n]
  else UInt8.ofNat (n % 128 + 128) :: sleb (n / 128)
termination_by n
decreasing_by omega

/-- Signed LEB128 decoder, returning an `Int` (the last group is sign
extended, as the binary format prescribes). -/
def slebDec : List UInt8 → Option (Int × List UInt8)
  | [] => none
  | b :: bs =>
    let x := b.toNat
    if x < 128 then
      some (if x < 64 then (x : Int) else (x : Int) - 128, bs)
    else match slebDec bs with
      | some (n, r) => some (((x : Int) - 128) + 128 * n, r)
      | none => none

/-- Signed LEB128 round-trips on non-negative values, in a stream. -/
theorem slebDec_sleb (n : Nat) (rest : List UInt8) :
    slebDec (sleb n ++ rest) = some ((n : Int), rest) := by
  induction n using sleb.induct with
  | case1 n h =>
      rw [sleb, if_pos h]
      simp [slebDec, toNat_ofNat_lt (by omega : n < 256), (by omega : n < 128), h]
  | case2 n h ih =>
      rw [sleb, if_neg h]
      have hb : (UInt8.ofNat (n % 128 + 128)).toNat = n % 128 + 128 :=
        toNat_ofNat_lt (by omega)
      simp only [List.cons_append, slebDec, hb, if_neg (by omega : ¬ n % 128 + 128 < 128), ih]
      have harith : ((n % 128 + 128 : Nat) : Int) - 128 + 128 * ((n / 128 : Nat) : Int)
          = (n : Int) := by omega
      rw [harith]

theorem sleb_ne_nil (n : Nat) : sleb n ≠ [] := by
  rw [sleb]; split <;> simp

end Kant.Wasm.Leb128
