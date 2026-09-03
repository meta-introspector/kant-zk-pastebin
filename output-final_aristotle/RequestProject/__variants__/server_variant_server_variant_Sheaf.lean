/-
# The M → H → E sheaf: address types, eigenspaces and encodings
Lean 4 port of `src/sheaf.rs`.

Every paste is a *section*: a Monster object `M` (the DASL address type),
a subgroup `H` (the `Cl(15,0,0)` eigenspace that selects a route) and the
data `E` (the encoding it is currently presented in).  Each encoding is
tagged with a Monster supersingular prime giving its "resolution level".

Proved here:

* the eight DASL type tags are distinct and fit the 4-bit field, and an
  address built with a tag decodes back to it (`daslType_roundTrip`);
* every encoding's prime is a Monster supersingular prime, except the
  identity encoding `raw` whose prime is `1` (`encoding_prime_monster`);
* distinct encodings carry distinct primes (`prime_injective`), so the
  resolution level identifies the encoding;
* encoding names round-trip (`fromName_name`).
-/
import Mathlib
import RequestProject.Kant.Dasl

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.Sheaf

open Kant.Dasl

/-- The eight DASL address types (4-bit field, bits 47–44). -/
inductive DaslType
  | monsterWalk | astNode | protocol | nestedCid | harmonicPath | shardId
  | eigenspace | hauptmodul
deriving DecidableEq, Repr, Fintype

/-- Numeric tag, as in the Rust `enum DaslType`. -/
def DaslType.tag : DaslType → Nat
  | .monsterWalk => 0
  | .astNode => 1
  | .protocol => 2
  | .nestedCid => 3
  | .harmonicPath => 4
  | .shardId => 5
  | .eigenspace => 6
  | .hauptmodul => 7

theorem DaslType.tag_lt (t : DaslType) : t.tag < 16 := by
  cases t <;> decide

theorem DaslType.tag_injective : Function.Injective DaslType.tag := by
  decide

/-- An address built with a type tag decodes back to that tag. -/
theorem daslType_roundTrip (t : DaslType) (payload : Nat) :
    cidType (mkCid t.tag payload) = t.tag := by
  rw [cidType_mkCid, Nat.mod_eq_of_lt t.tag_lt]

/-- `Cl(15,0,0)` eigenspaces. -/
inductive EigenSpace
  | earth | spoke | hub | clock
deriving DecidableEq, Repr, Fintype

/-- The primes carried by the Earth eigenspace, as documented in
`sheaf.rs`. -/
def EigenSpace.primes : EigenSpace → List Nat
  | .earth => [2, 3, 5, 7, 11, 13, 47]
  | .spoke => [17, 29, 31, 41, 59, 71]
  | .hub => [19, 23]
  | .clock => []

/-- Every eigenspace is spanned by Monster supersingular primes. -/
theorem eigenSpace_primes_monster (e : EigenSpace) :
    ∀ p ∈ e.primes, p ∈ monsterPrimes := by
  cases e <;> decide

/-- Earth, Spoke and Hub partition the fifteen supersingular primes. -/
theorem eigenSpace_primes_partition :
    (EigenSpace.earth.primes ++ EigenSpace.spoke.primes ++ EigenSpace.hub.primes).length
      = monsterPrimes.length ∧
    ∀ p ∈ monsterPrimes,
      p ∈ EigenSpace.earth.primes ++ EigenSpace.spoke.primes ++ EigenSpace.hub.primes := by
  constructor <;> decide

/-- Presentation formats, each at a Monster resolution level. -/
inductive Encoding
  | raw | base64 | morse | split | qr | dtmf | numbers | stego | ipfs | dasl
deriving DecidableEq, Repr, Fintype

/-- The Monster prime associated with an encoding's resolution level. -/
def Encoding.prime : Encoding → Nat
  | .raw => 1
  | .base64 => 2
  | .morse => 3
  | .split => 5
  | .qr => 7
  | .dtmf => 11
  | .numbers => 13
  | .stego => 47
  | .ipfs => 59
  | .dasl => 71

/-- The identifier used in URLs and metadata. -/
def Encoding.name : Encoding → List Char
  | .raw => "raw".toList
  | .base64 => "base64".toList
  | .morse => "morse".toList
  | .split => "split".toList
  | .qr => "qr".toList
  | .dtmf => "dtmf".toList
  | .numbers => "numbers".toList
  | .stego => "stego".toList
  | .ipfs => "ipfs".toList
  | .dasl => "dasl".toList

/-- Parse an encoding name, defaulting to `raw` as upstream does. -/
def Encoding.fromName (s : List Char) : Encoding :=
  if s = "base64".toList then .base64
  else if s = "morse".toList then .morse
  else if s = "split".toList then .split
  else if s = "qr".toList then .qr
  else if s = "dtmf".toList then .dtmf
  else if s = "numbers".toList then .numbers
  else if s = "stego".toList then .stego
  else if s = "ipfs".toList then .ipfs
  else if s = "dasl".toList then .dasl
  else .raw

/-- Names round-trip. -/
theorem fromName_name (e : Encoding) : Encoding.fromName e.name = e := by
  cases e <;> native_decide

/-- Distinct encodings sit at distinct resolution levels. -/
theorem prime_injective : Function.Injective Encoding.prime := by
  decide

/-- Every encoding except the identity sits at a Monster supersingular
prime. -/
theorem encoding_prime_monster (e : Encoding) :
    e = .raw ∨ e.prime ∈ monsterPrimes := by
  cases e <;> simp [Encoding.prime, monsterPrimes]

/-- The three encodings of the attack triple `47 · 59 · 71 = 196883` are
exactly stego, IPFS and DASL — the three that leave the machine. -/
theorem attackTriple_encodings :
    Encoding.stego.prime * Encoding.ipfs.prime * Encoding.dasl.prime = 196883 := by
  decide

/-- A sheaf section: the M → H → E triple attached to a paste. -/
structure Section where
  addressType : DaslType
  eigen : EigenSpace
  encoding : Encoding
deriving DecidableEq, Repr

/-- The number of distinct sections is `8 · 4 · 10 = 320`. -/
theorem daslType_card : Fintype.card DaslType = 8 := by decide
theorem eigenSpace_card : Fintype.card EigenSpace = 4 := by decide
theorem encoding_card : Fintype.card Encoding = 10 := by decide

theorem section_card : Fintype.card (DaslType × EigenSpace × Encoding) = 320 := by
  simp [Fintype.card_prod, daslType_card, eigenSpace_card, encoding_card]

end Kant.Sheaf
