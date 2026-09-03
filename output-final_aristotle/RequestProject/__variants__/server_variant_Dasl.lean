/-
# DASL `0xDA51` content addressing — Lean 4 port of `src/dasl.rs`

The upstream Rust module packs content addresses into 64-bit words with a
fixed bit layout

```
[63..48] = 0xDA51 prefix   [47..44] = type nibble   [43..0] = payload
```

and navigates a "Monster orbifold" `Z/71 × Z/59 × Z/47`.

Here the layout is modelled over `Nat` (so the arithmetic is exact and the
proofs are about the real bit-fields, not about a wrapping machine word),
and every structural claim the Rust code silently relies on is proved:

* `decode ∘ mkCid = id` on well-formed fields (Types 3/4/5 all go through
  `mkCid`), and `decode` rejects non-DASL words;
* every CID really is a 64-bit word;
* orbifold coordinates always land in `Z/71 × Z/59 × Z/47`;
* the three orbifold moves are a genuine additive action (additive in the
  step, commuting, periodic, invertible);
* `merge_cids` is a commutative, associative, prefix-preserving XOR with
  unit and self-inverse — i.e. the "URL composition algebra" of
  `SNEAKERNET.md` is an elementary abelian 2-group, so the root address of
  a paste DAG is independent of traversal order.
-/
import Mathlib
import RequestProject.Kant.Bytes

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.Dasl

open Kant.Bytes

/-! ## Monster data (`MONSTER_PRIMES`, `MONSTER_EXPONENTS`, `ATTACK_TRIPLE`) -/

/-- The 15 supersingular primes dividing the order of the Monster. -/
def monsterPrimes : List Nat := [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 41, 47, 59, 71]

/-- Exponents of `|M| = 2^46 · 3^20 · 5^9 · 7^6 · 11^2 · 13^3 · 17 ⋯ 71`. -/
def monsterExponents : List Nat := [46, 20, 9, 6, 2, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1]

/-- `ATTACK_TRIPLE`: the three largest supersingular primes. -/
def attackTriple : Nat × Nat × Nat := (47, 59, 71)

theorem monsterPrimes_all_prime : ∀ p ∈ monsterPrimes, Nat.Prime p := by
  decide

theorem monsterPrimes_length : monsterPrimes.length = 15 := rfl

theorem monsterExponents_length : monsterExponents.length = 15 := rfl

/-- `47 · 59 · 71 = 196883`, the dimension of the smallest faithful
representation of the Monster — the comment in `dasl.rs`. -/
theorem attackTriple_prod :
    attackTriple.1 * attackTriple.2.1 * attackTriple.2.2 = 196883 := by
  decide

/-- The order of the Monster group, as factored in `dasl.rs`. -/
def monsterOrder : Nat :=
  (List.zipWith (fun p e => p ^ e) monsterPrimes monsterExponents).prod

theorem monsterOrder_eq :
    monsterOrder = 808017424794512875886459904961710757005754368000000000 := by
  native_decide

/-! ## The `0xDA51` bit layout -/

/-- The 16-bit DASL magic prefix. -/
def daslPrefix : Nat := 0xDA51

/-- Assemble a DASL address from a 4-bit type tag and a 44-bit payload.
Fields are truncated exactly as the Rust masks (`& 0xF`, …) do. -/
def mkCid (typ payload : Nat) : Nat :=
  daslPrefix * 2 ^ 48 + (typ % 16) * 2 ^ 44 + payload % 2 ^ 44

/-- The 16 high bits of a word. -/
def cidPrefix (c : Nat) : Nat := c / 2 ^ 48

/-- The type nibble. -/
def cidType (c : Nat) : Nat := c / 2 ^ 44 % 16

/-- The 44-bit payload. -/
def cidPayload (c : Nat) : Nat := c % 2 ^ 44

/-- `dasl::decode`: recognise a DASL word and split it into
`(type, payload)`; anything without the `0xDA51` prefix is rejected. -/
def decode (c : Nat) : Option (Nat × Nat) :=
  if cidPrefix c = daslPrefix then some (cidType c, cidPayload c) else none

@[simp] theorem cidPrefix_mkCid (t p : Nat) : cidPrefix (mkCid t p) = daslPrefix := by
  have ht : t % 16 < 16 := Nat.mod_lt _ (by norm_num)
  have hp : p % 2 ^ 44 < 2 ^ 44 := Nat.mod_lt _ (by positivity)
  simp only [cidPrefix, mkCid, daslPrefix]
  norm_num at ht hp ⊢
  omega

@[simp] theorem cidType_mkCid (t p : Nat) : cidType (mkCid t p) = t % 16 := by
  have ht : t % 16 < 16 := Nat.mod_lt _ (by norm_num)
  have hp : p % 2 ^ 44 < 2 ^ 44 := Nat.mod_lt _ (by positivity)
  simp only [cidType, mkCid, daslPrefix]
  norm_num at ht hp ⊢
  omega

@[simp] theorem cidPayload_mkCid (t p : Nat) : cidPayload (mkCid t p) = p % 2 ^ 44 := by
  have hp : p % 2 ^ 44 < 2 ^ 44 := Nat.mod_lt _ (by positivity)
  simp only [cidPayload, mkCid, daslPrefix]
  norm_num at hp ⊢
  omega

/-- **Round-trip.** Decoding an assembled address returns its fields. -/
@[simp] theorem decode_mkCid (t p : Nat) :
    decode (mkCid t p) = some (t % 16, p % 2 ^ 44) := by
  simp [decode]

/-- On already-reduced fields the round-trip is exact. -/
theorem decode_mkCid_of_lt {t p : Nat} (ht : t < 16) (hp : p < 2 ^ 44) :
    decode (mkCid t p) = some (t, p) := by
  rw [decode_mkCid, Nat.mod_eq_of_lt ht, Nat.mod_eq_of_lt hp]

/-- Non-DASL words are rejected. -/
theorem decode_eq_none {c : Nat} (h : cidPrefix c ≠ daslPrefix) : decode c = none := by
  simp [decode, h]

/-- Every DASL address fits in 64 bits. -/
theorem mkCid_lt (t p : Nat) : mkCid t p < 2 ^ 64 := by
  have ht : t % 16 < 16 := Nat.mod_lt _ (by norm_num)
  have hp : p % 2 ^ 44 < 2 ^ 44 := Nat.mod_lt _ (by positivity)
  simp only [mkCid, daslPrefix]
  norm_num at ht hp ⊢
  omega

/-- Addresses are determined by their fields: the layout is injective. -/
theorem mkCid_injective {t₁ p₁ t₂ p₂ : Nat} (ht₁ : t₁ < 16) (hp₁ : p₁ < 2 ^ 44)
    (ht₂ : t₂ < 16) (hp₂ : p₂ < 2 ^ 44) (h : mkCid t₁ p₁ = mkCid t₂ p₂) :
    t₁ = t₂ ∧ p₁ = p₂ := by
  have h1 : decode (mkCid t₁ p₁) = some (t₁, p₁) := decode_mkCid_of_lt ht₁ hp₁
  have h2 : decode (mkCid t₂ p₂) = some (t₂, p₂) := decode_mkCid_of_lt ht₂ hp₂
  rw [h, h2] at h1
  have := Option.some.inj h1
  exact ⟨(Prod.mk.injEq _ _ _ _ ▸ this).1.symm, (Prod.mk.injEq _ _ _ _ ▸ this).2.symm⟩

/-! ## Concrete address constructors (Types 3–5 of `dasl.rs`) -/

/-- Byte `i` of a digest, `0` past the end. -/
def byteAt (h : Blob) (i : Nat) : Nat := (h[i]?.getD 0).toNat

/-- Type 3: nested, content-addressed CID.  The payload carries the
orbifold shard/hecke/bott bytes plus 20 bits of digest, as upstream. -/
def nestedCidPayload (h : Blob) : Nat :=
  byteAt h 0 % 71 * 2 ^ 36 + byteAt h 1 % 59 * 2 ^ 28 + byteAt h 2 % 47 * 2 ^ 20
    + (byteAt h 3 * 2 ^ 12 + byteAt h 4 * 2 ^ 4 + byteAt h 5 / 16) % 2 ^ 20

/-- Type 3 address of a byte string (`nested_cid`). -/
def nestedCid (data : Blob) : Nat := mkCid 3 (nestedCidPayload (digest data))

/-- Type 5: shard identifier for distributed storage (`shard_cid`). -/
def shardCid (primeIdx replica zone node : Nat) : Nat :=
  mkCid 5 ((primeIdx % 16) * 2 ^ 40 + (replica % 16) * 2 ^ 36 + (zone % 256) * 2 ^ 28
            + node % 2 ^ 28)

/-- Type 4: harmonic routing path between the 10-fold and 8-fold ways. -/
def harmonicPathCid (source dest harmonic : Nat) : Nat :=
  mkCid 4 ((source % 16) * 2 ^ 40 + (dest % 16) * 2 ^ 36 + (harmonic % 256) * 2 ^ 28)

/-- Every constructed address decodes to its declared type. -/
@[simp] theorem cidType_nestedCid (d : Blob) : cidType (nestedCid d) = 3 := by
  simp [nestedCid]

@[simp] theorem cidType_shardCid (a b c d : Nat) : cidType (shardCid a b c d) = 5 := by
  simp [shardCid]

@[simp] theorem cidType_harmonicPathCid (a b c : Nat) : cidType (harmonicPathCid a b c) = 4 := by
  simp [harmonicPathCid]

/-- Every constructed address is a valid DASL word. -/
@[simp] theorem cidPrefix_nestedCid (d : Blob) : cidPrefix (nestedCid d) = daslPrefix := by
  simp [nestedCid]

/-- Content addressing is a function of the content only. -/
theorem nestedCid_deterministic {a b : Blob} (h : a = b) : nestedCid a = nestedCid b := by
  rw [h]

/-! ## Orbifold coordinates and the `Z/71 × Z/59 × Z/47` action -/

/-- A point of the Monster base space `Z/71 × Z/59 × Z/47`. -/
structure Orbifold where
  l : Nat
  m : Nat
  n : Nat
deriving DecidableEq, Repr

/-- Well-formedness: each coordinate is reduced. -/
def Orbifold.valid (o : Orbifold) : Prop := o.l < 71 ∧ o.m < 59 ∧ o.n < 47

instance (o : Orbifold) : Decidable o.valid := by
  unfold Orbifold.valid; infer_instance

/-- Little-endian 32-bit read at position `i` of a digest. -/
def le32 (h : Blob) (i : Nat) : Nat :=
  byteAt h i + byteAt h (i + 1) * 2 ^ 8 + byteAt h (i + 2) * 2 ^ 16 + byteAt h (i + 3) * 2 ^ 24

/-- `orbifold_coords`: map content into the Monster base space. -/
def orbifoldCoords (data : Blob) : Orbifold :=
  let h := digest data
  ⟨le32 h 0 % 71, le32 h 4 % 59, le32 h 8 % 47⟩

theorem orbifoldCoords_valid (data : Blob) : (orbifoldCoords data).valid :=
  ⟨Nat.mod_lt _ (by norm_num), Nat.mod_lt _ (by norm_num), Nat.mod_lt _ (by norm_num)⟩

/-- 71-fold orbifold rotation. -/
def rotate71 (o : Orbifold) (k : Nat) : Orbifold := ⟨(o.l + k) % 71, o.m, o.n⟩

/-- 59-fold orbifold reflection. -/
def reflect59 (o : Orbifold) (k : Nat) : Orbifold := ⟨o.l, (o.m + k) % 59, o.n⟩

/-- 47-fold orbifold duality. -/
def dual47 (o : Orbifold) (k : Nat) : Orbifold := ⟨o.l, o.m, (o.n + k) % 47⟩

theorem rotate71_valid {o : Orbifold} (h : o.valid) (k : Nat) : (rotate71 o k).valid :=
  ⟨Nat.mod_lt _ (by norm_num), h.2.1, h.2.2⟩

theorem reflect59_valid {o : Orbifold} (h : o.valid) (k : Nat) : (reflect59 o k).valid :=
  ⟨h.1, Nat.mod_lt _ (by norm_num), h.2.2⟩

theorem dual47_valid {o : Orbifold} (h : o.valid) (k : Nat) : (dual47 o k).valid :=
  ⟨h.1, h.2.1, Nat.mod_lt _ (by norm_num)⟩

/-- The rotation is additive in its step. -/
theorem rotate71_add (o : Orbifold) (j k : Nat) :
    rotate71 (rotate71 o j) k = rotate71 o (j + k) := by
  simp only [rotate71, Orbifold.mk.injEq, and_true]
  omega

theorem reflect59_add (o : Orbifold) (j k : Nat) :
    reflect59 (reflect59 o j) k = reflect59 o (j + k) := by
  simp only [reflect59, Orbifold.mk.injEq, true_and, and_true]
  omega

theorem dual47_add (o : Orbifold) (j k : Nat) :
    dual47 (dual47 o j) k = dual47 o (j + k) := by
  simp only [dual47, Orbifold.mk.injEq, true_and]
  omega

/-- The rotation has period 71 on valid points. -/
theorem rotate71_period {o : Orbifold} (h : o.valid) : rotate71 o 71 = o := by
  obtain ⟨hl, -, -⟩ := h
  simp only [rotate71, Nat.add_mod_right, Nat.mod_eq_of_lt hl]

theorem reflect59_period {o : Orbifold} (h : o.valid) : reflect59 o 59 = o := by
  obtain ⟨-, hm, -⟩ := h
  simp only [reflect59, Nat.add_mod_right, Nat.mod_eq_of_lt hm]

theorem dual47_period {o : Orbifold} (h : o.valid) : dual47 o 47 = o := by
  obtain ⟨-, -, hn⟩ := h
  simp only [dual47, Nat.add_mod_right, Nat.mod_eq_of_lt hn]

/-- The three moves act on independent coordinates, so they commute. -/
theorem rotate71_reflect59_comm (o : Orbifold) (j k : Nat) :
    reflect59 (rotate71 o j) k = rotate71 (reflect59 o k) j := rfl

theorem rotate71_dual47_comm (o : Orbifold) (j k : Nat) :
    dual47 (rotate71 o j) k = rotate71 (dual47 o k) j := rfl

theorem reflect59_dual47_comm (o : Orbifold) (j k : Nat) :
    dual47 (reflect59 o j) k = reflect59 (dual47 o k) j := rfl

/-- Every move is invertible: the orbifold moves form a group action. -/
theorem rotate71_inverse {o : Orbifold} (h : o.valid) {k : Nat} (hk : k ≤ 71) :
    rotate71 (rotate71 o k) (71 - k) = o := by
  rw [rotate71_add]
  have hk' : k + (71 - k) = 71 := by omega
  rw [hk', rotate71_period h]

theorem reflect59_inverse {o : Orbifold} (h : o.valid) {k : Nat} (hk : k ≤ 59) :
    reflect59 (reflect59 o k) (59 - k) = o := by
  rw [reflect59_add]
  have hk' : k + (59 - k) = 59 := by omega
  rw [hk', reflect59_period h]

theorem dual47_inverse {o : Orbifold} (h : o.valid) {k : Nat} (hk : k ≤ 47) :
    dual47 (dual47 o k) (47 - k) = o := by
  rw [dual47_add]
  have hk' : k + (47 - k) = 47 := by omega
  rw [hk', dual47_period h]

/-! ## Bott / ten-fold tables and the harmonic slide -/

/-- `BOTT_COORDS`, the 8-fold way. -/
def bottCoords : List Orbifold :=
  [⟨0,0,0⟩, ⟨9,7,6⟩, ⟨18,14,12⟩, ⟨27,21,18⟩, ⟨36,28,24⟩, ⟨45,35,30⟩, ⟨54,42,36⟩, ⟨63,49,42⟩]

/-- `TENFOLD_COORDS`, the Altland–Zirnbauer classes. -/
def tenfoldCoords : List Orbifold :=
  [⟨0,11,37⟩, ⟨1,15,37⟩, ⟨2,19,37⟩, ⟨3,23,37⟩, ⟨4,27,37⟩, ⟨5,31,37⟩,
   ⟨6,35,37⟩, ⟨7,39,37⟩, ⟨8,43,37⟩, ⟨9,47,37⟩, ⟨10,51,37⟩]

theorem bottCoords_length : bottCoords.length = 8 := rfl
theorem tenfoldCoords_length : tenfoldCoords.length = 11 := rfl

theorem bottCoords_valid : ∀ o ∈ bottCoords, o.valid := by decide
theorem tenfoldCoords_valid : ∀ o ∈ tenfoldCoords, o.valid := by decide

/-- The eight Bott points are pairwise distinct: the 8-fold way embeds in
the orbifold. -/
theorem bottCoords_nodup : bottCoords.Nodup := by decide

/-- The eleven ten-fold points are pairwise distinct. -/
theorem tenfoldCoords_nodup : tenfoldCoords.Nodup := by decide

/-- `harmonic_slide`: bridge between the 10-fold and 8-fold CID spaces. -/
def harmonicSlide (tenfoldIdx bottIdx : Nat) : Orbifold :=
  let t := tenfoldCoords[tenfoldIdx]?.getD ⟨0,0,0⟩
  let b := bottCoords[bottIdx]?.getD ⟨0,0,0⟩
  ⟨(t.l + b.l) % 71, (t.m + b.m) % 59, (t.n + b.n) % 47⟩

theorem harmonicSlide_valid (i j : Nat) : (harmonicSlide i j).valid := by
  refine ⟨?_, ?_, ?_⟩ <;> simp only [harmonicSlide] <;> omega

/-! ## `merge_cids`: the URL composition algebra -/

/-- `merge_cids`: XOR the low 48 bits, keep the `0xDA51` prefix. -/
def mergeCids (c₁ c₂ : Nat) : Nat :=
  daslPrefix * 2 ^ 48 + ((c₁ % 2 ^ 48) ^^^ (c₂ % 2 ^ 48))

/-- The neutral element of the merge algebra. -/
def mergeUnit : Nat := daslPrefix * 2 ^ 48

theorem mergeCids_lt_pow (c₁ c₂ : Nat) : (c₁ % 2 ^ 48) ^^^ (c₂ % 2 ^ 48) < 2 ^ 48 :=
  Nat.xor_lt_two_pow (Nat.mod_lt _ (by positivity)) (Nat.mod_lt _ (by positivity))

/-- Merging preserves the DASL prefix. -/
@[simp] theorem cidPrefix_mergeCids (c₁ c₂ : Nat) :
    cidPrefix (mergeCids c₁ c₂) = daslPrefix := by
  have h := mergeCids_lt_pow c₁ c₂
  simp only [cidPrefix, mergeCids, daslPrefix]
  norm_num at h ⊢
  omega

theorem mergeCids_payload (c₁ c₂ : Nat) :
    mergeCids c₁ c₂ % 2 ^ 48 = (c₁ % 2 ^ 48) ^^^ (c₂ % 2 ^ 48) := by
  have h := mergeCids_lt_pow c₁ c₂
  simp only [mergeCids, daslPrefix]
  norm_num at h ⊢
  omega

theorem mergeCids_comm (c₁ c₂ : Nat) : mergeCids c₁ c₂ = mergeCids c₂ c₁ := by
  simp [mergeCids, Nat.xor_comm]

/-- Merging an address with itself annihilates it: self-inverse. -/
theorem mergeCids_self (c : Nat) : mergeCids c c = mergeUnit := by
  rw [mergeCids, Nat.xor_self, mergeUnit, Nat.add_zero]

theorem mergeCids_zero (c : Nat) (h : c < 2 ^ 48) :
    mergeCids 0 c = daslPrefix * 2 ^ 48 + c := by
  rw [mergeCids, Nat.zero_mod, Nat.zero_xor, Nat.mod_eq_of_lt h]

/-- `mergeUnit` is neutral for addresses that fit in 48 bits. -/
theorem mergeCids_unit (c : Nat) (h : c < 2 ^ 48) :
    mergeCids mergeUnit c = daslPrefix * 2 ^ 48 + c := by
  have h1 : mergeUnit % 2 ^ 48 = 0 := Nat.mul_mod_left daslPrefix (2 ^ 48)
  rw [mergeCids, h1, Nat.zero_xor, Nat.mod_eq_of_lt h]

/-- Merging is associative, so a DAG of pastes has a well-defined root
address independent of the bracketing. -/
theorem mergeCids_assoc (c₁ c₂ c₃ : Nat) :
    mergeCids (mergeCids c₁ c₂) c₃ = mergeCids c₁ (mergeCids c₂ c₃) := by
  have e1 : mergeCids (mergeCids c₁ c₂) c₃
      = daslPrefix * 2 ^ 48 + ((mergeCids c₁ c₂ % 2 ^ 48) ^^^ (c₃ % 2 ^ 48)) := rfl
  have e2 : mergeCids c₁ (mergeCids c₂ c₃)
      = daslPrefix * 2 ^ 48 + ((c₁ % 2 ^ 48) ^^^ (mergeCids c₂ c₃ % 2 ^ 48)) := rfl
  rw [e1, e2, mergeCids_payload, mergeCids_payload, Nat.xor_assoc]

/-- Merge-fold of a whole list of addresses (the root CID of a paste DAG). -/
def mergeAll (l : List Nat) : Nat :=
  daslPrefix * 2 ^ 48 + l.foldl (fun a c => a ^^^ (c % 2 ^ 48)) 0

instance : RightCommutative (fun (a c : Nat) => a ^^^ (c % 2 ^ 48)) :=
  ⟨by intro b a c; simp only [Nat.xor_assoc]; rw [Nat.xor_comm (a % 2 ^ 48)]⟩

/-- **Order independence.** The root address of a set of pastes does not
depend on the order in which peers merge them — the key property that
makes the sneakernet's "URL composition algebra" well defined. -/
theorem mergeAll_perm {l₁ l₂ : List Nat} (h : l₁.Perm l₂) : mergeAll l₁ = mergeAll l₂ := by
  simp only [mergeAll, h.foldl_eq 0]

@[simp] theorem mergeAll_nil : mergeAll [] = mergeUnit := rfl

/-- Appending one more address to a merge-fold is one more `merge_cids`. -/
theorem mergeAll_append_singleton (l : List Nat) (c : Nat) :
    mergeAll (l ++ [c]) = mergeCids (mergeAll l) c := by
  have hlt : l.foldl (fun a c => a ^^^ (c % 2 ^ 48)) 0 < 2 ^ 48 := by
    have : ∀ (xs : List Nat) (a : Nat), a < 2 ^ 48 →
        xs.foldl (fun a c => a ^^^ (c % 2 ^ 48)) a < 2 ^ 48 := by
      intro xs
      induction xs with
      | nil => intro a ha; simpa using ha
      | cons x xs ih =>
          intro a ha
          exact ih _ (Nat.xor_lt_two_pow ha (Nat.mod_lt _ (by positivity)))
    exact this l 0 (by positivity)
  have hmod : (daslPrefix * 2 ^ 48 + l.foldl (fun a c => a ^^^ (c % 2 ^ 48)) 0) % 2 ^ 48
      = l.foldl (fun a c => a ^^^ (c % 2 ^ 48)) 0 := by
    simp only [daslPrefix]
    norm_num at hlt ⊢
    omega
  simp only [mergeAll, List.foldl_append, List.foldl_cons, List.foldl_nil, mergeCids, hmod]

/-! ## Printing (`dasl_hex`) -/

/-- `dasl_hex`: `0x` followed by 16 lowercase hex digits. -/
def daslHex (c : Nat) : List Char :=
  '0' :: 'x' :: ((List.range 16).map (fun i => hexDigit (c / 16 ^ (15 - i) % 16)))

theorem daslHex_length (c : Nat) : (daslHex c).length = 18 := by
  simp [daslHex]

end Kant.Dasl
