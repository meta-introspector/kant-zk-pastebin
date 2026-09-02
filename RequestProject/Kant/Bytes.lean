/-
# Bytes, digests and hex — the byte-level substrate of the port

Lean 4 port of the byte handling that the original `kant-zk-pastebin`
(Rust) performs with `sha2`, `hex` and `serde`.

The upstream code hashes content with SHA-256 and prints the digest with
`hex::encode`.  Re-implementing SHA-256 is orthogonal to the semantics we
want to verify, so this module

* provides a concrete, executable 64-bit FNV-1a based digest so that the
  whole pipeline can actually be run, and
* proves the properties the rest of the development relies on:
  determinism, fixed width and hex round-tripping.

Everything here is computable, so it survives compilation to C / WASM.
-/
import Mathlib

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.Bytes

/-- Raw content is a list of bytes. -/
abbrev Blob := List UInt8

/-! ## Hex encoding -/

/-- The lowercase hex digit for a value `< 16`. -/
def hexDigit (n : Nat) : Char :=
  if n < 10 then Char.ofNat (48 + n) else Char.ofNat (87 + n)

/-- Hex-encode a single byte (two lowercase digits). -/
def hexByte (b : UInt8) : List Char :=
  [hexDigit (b.toNat / 16), hexDigit (b.toNat % 16)]

/-- `hex::encode` : lowercase hex string of a byte string. -/
def hexEncode (bs : Blob) : List Char :=
  bs.flatMap hexByte

/-- Value of a lowercase hex digit, `none` if the character is not one. -/
def hexVal (c : Char) : Option Nat :=
  if '0' ≤ c ∧ c ≤ '9' then some (c.toNat - 48)
  else if 'a' ≤ c ∧ c ≤ 'f' then some (c.toNat - 87)
  else none

/-- Inverse of `hexEncode` on well-formed input. -/
def hexDecode : List Char → Option Blob
  | [] => some []
  | [_] => none
  | c₁ :: c₂ :: rest => do
      let h ← hexVal c₁
      let l ← hexVal c₂
      let tail ← hexDecode rest
      pure (UInt8.ofNat (16 * h + l) :: tail)

theorem hexEncode_length (bs : Blob) : (hexEncode bs).length = 2 * bs.length := by
  induction bs with
  | nil => simp [hexEncode]
  | cons b bs ih =>
      simp [hexEncode, hexByte] at ih ⊢
      omega

theorem hexVal_hexDigit {n : Nat} (h : n < 16) : hexVal (hexDigit n) = some n := by
  interval_cases n <;> rfl

/-- Hex encoding round-trips: `hex::decode ∘ hex::encode = id`. -/
theorem hexDecode_hexEncode (bs : Blob) : hexDecode (hexEncode bs) = some bs := by
  induction bs with
  | nil => rfl
  | cons b bs ih =>
      have hb : b.toNat < 256 := b.toNat_lt_size
      have h1 : b.toNat / 16 < 16 := by omega
      have h2 : b.toNat % 16 < 16 := Nat.mod_lt _ (by norm_num)
      simp only [hexEncode, List.flatMap_cons, hexByte, List.cons_append, List.nil_append,
        hexDecode, hexVal_hexDigit h1, hexVal_hexDigit h2, Option.bind_eq_bind]

      show (do let tail ← hexDecode (hexEncode bs)
               pure (UInt8.ofNat (16 * (b.toNat / 16) + b.toNat % 16) :: tail)) = _
      rw [ih]
      have h3 : 16 * (b.toNat / 16) + b.toNat % 16 = b.toNat := by omega
      simp [h3]

/-! ## A concrete executable digest (FNV-1a, 64 bit)

The upstream witness is `sha256(content)`.  We keep the *shape* of that
construction — a deterministic function from bytes to a fixed number of
bytes — but use FNV-1a so that the port stays self-contained and runs.
All downstream results are stated either for this digest or for an
arbitrary digest function, never for SHA-256 specifically. -/

/-- FNV-1a 64-bit offset basis. -/
def fnvOffset : UInt64 := 14695981039346656037

/-- FNV-1a 64-bit prime. -/
def fnvPrime : UInt64 := 1099511628211

/-- One FNV-1a step. -/
def fnvStep (h : UInt64) (b : UInt8) : UInt64 :=
  (h ^^^ b.toUInt64) * fnvPrime

/-- FNV-1a 64-bit hash of a byte string. -/
def fnv1a (bs : Blob) : UInt64 :=
  bs.foldl fnvStep fnvOffset

/-- Big-endian byte expansion of a `UInt64`. -/
def u64Bytes (x : UInt64) : Blob :=
  (List.range 8).map (fun i => (x >>> (UInt64.ofNat (8 * (7 - i)))).toUInt8)

/-- A 32-byte digest, built by iterating FNV-1a over four salted rounds,
mirroring the width of the SHA-256 witness used upstream. -/
def digest (bs : Blob) : Blob :=
  (List.range 4).flatMap fun i => u64Bytes (fnv1a (UInt8.ofNat i :: bs))

/-- The witness string of a paste: hex of its digest, as in `Paste::new`. -/
def witness (bs : Blob) : List Char := hexEncode (digest bs)

@[simp] theorem u64Bytes_length (x : UInt64) : (u64Bytes x).length = 8 := by
  simp [u64Bytes]

/-- The digest has the same width as the SHA-256 witness it replaces. -/
@[simp] theorem digest_length (bs : Blob) : (digest bs).length = 32 := by
  simp [digest, List.length_flatMap]

/-- The hex witness is 64 characters wide, exactly as asserted by the
upstream test `test_paste_creation`. -/
@[simp] theorem witness_length (bs : Blob) : (witness bs).length = 64 := by
  simp [witness, hexEncode_length]

/-- Content addressing is deterministic: equal content, equal witness. -/
theorem witness_deterministic {a b : Blob} (h : a = b) : witness a = witness b := by
  rw [h]

end Kant.Bytes
