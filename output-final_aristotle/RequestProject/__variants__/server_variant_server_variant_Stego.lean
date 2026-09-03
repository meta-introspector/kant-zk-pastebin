/-
# Covert channels: LSB steganography in PNG / GIF / video pixel data
Lean 4 port of the `stego.rs` channel referenced by `SNEAKERNET.md`
(`Encoding::Stego`, the Monster prime `p = 47`).

A status update — a CID, a QR payload, a paste fragment — is hidden in
the least significant bits of a carrier image's samples, and the carrier
is then posted as an ordinary PNG/SVG raster/animated GIF frame.  Two
things must hold for that to be a usable covert channel:

* **the message survives**: `extract_embed` recovers the payload bit for
  bit, and `extractBlob_embedBlob` recovers the byte string;
* **the carrier is barely disturbed**: `embed_preserves_high_bits` shows
  every sample changes by at most one unit (the top seven bits are
  untouched), and `embed_lt_256` shows samples stay in range, so the
  image is still a valid 8-bit raster.
-/
import Mathlib
import RequestProject.Kant.Bytes

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.Stego

/-- Carrier samples: one 8-bit channel value per entry (PNG/GIF pixels,
video luma samples, SVG colour components). -/
abbrev Carrier := List Nat

/-- A sample list is a valid 8-bit raster. -/
def Carrier.valid (c : Carrier) : Prop := ∀ v ∈ c, v < 256

/-! ## Bytes ↔ bits -/

/-- The eight bits of a byte, most significant first. -/
def byteBits (n : Nat) : List Bool :=
  (List.range 8).map (fun i => n / 2 ^ (7 - i) % 2 == 1)

/-- Bit-serialise a byte string. -/
def toBits (bs : List Nat) : List Bool := bs.flatMap byteBits

/-- Reassemble a byte from eight bits, most significant first. -/
def bitsByte (bs : List Bool) : Nat :=
  (bs.zipIdx.map (fun p => if p.1 then 2 ^ (7 - p.2) else 0)).sum

/-- Reassemble a byte string from bits (trailing partial group dropped). -/
def fromBits : List Bool → List Nat
  | b₀ :: b₁ :: b₂ :: b₃ :: b₄ :: b₅ :: b₆ :: b₇ :: rest =>
      bitsByte [b₀, b₁, b₂, b₃, b₄, b₅, b₆, b₇] :: fromBits rest
  | _ => []

@[simp] theorem byteBits_length (n : Nat) : (byteBits n).length = 8 := by
  simp [byteBits]

set_option maxRecDepth 10000 in
/-- Byte ↔ bits round-trips for genuine bytes. -/
theorem bitsByte_byteBits {n : Nat} (h : n < 256) : bitsByte (byteBits n) = n := by
  interval_cases n <;> decide

/-- Bit serialisation round-trips. -/
theorem fromBits_toBits {bs : List Nat} (h : ∀ v ∈ bs, v < 256) : fromBits (toBits bs) = bs := by
  induction bs with
  | nil => rfl
  | cons b bs ih =>
      have hb : b < 256 := h b (by simp)
      have hrest : ∀ v ∈ bs, v < 256 := fun v hv => h v (by simp [hv])
      have hbits : byteBits b = [b / 2 ^ 7 % 2 == 1, b / 2 ^ 6 % 2 == 1, b / 2 ^ 5 % 2 == 1,
          b / 2 ^ 4 % 2 == 1, b / 2 ^ 3 % 2 == 1, b / 2 ^ 2 % 2 == 1, b / 2 ^ 1 % 2 == 1,
          b / 2 ^ 0 % 2 == 1] := by
        simp [byteBits, List.range_succ]
      rw [toBits, List.flatMap_cons, hbits]
      show bitsByte _ :: fromBits (toBits bs) = _
      rw [ih hrest, ← hbits, bitsByte_byteBits hb]

/-! ## Embedding -/

/-- Overwrite the least significant bits of the carrier with a bit
stream.  Samples beyond the payload are left untouched. -/
def embedBits : Carrier → List Bool → Carrier
  | cs, [] => cs
  | [], _ => []
  | c :: cs, b :: bs => (2 * (c / 2) + (if b then 1 else 0)) :: embedBits cs bs

/-- Read `n` least significant bits back out of a carrier. -/
def extractBits (n : Nat) (cs : Carrier) : List Bool :=
  (cs.take n).map (fun c => c % 2 == 1)

@[simp] theorem embedBits_length (cs : Carrier) (bs : List Bool) :
    (embedBits cs bs).length = cs.length := by
  induction cs generalizing bs with
  | nil => cases bs <;> simp [embedBits]
  | cons c cs ih => cases bs <;> simp [embedBits, ih]

/-- **The payload survives.** -/
theorem extract_embed {cs : Carrier} {bs : List Bool} (h : bs.length ≤ cs.length) :
    extractBits bs.length (embedBits cs bs) = bs := by
  induction bs generalizing cs with
  | nil => simp [extractBits]
  | cons b bs ih =>
      cases cs with
      | nil => simp at h
      | cons c cs =>
          have h' : bs.length ≤ cs.length := by simpa using h
          have hbit : ((2 * (c / 2) + if b = true then 1 else 0) % 2 == 1) = b := by
            cases b <;> simp
          have htail := ih h'
          unfold extractBits at htail
          simp only [embedBits, extractBits, List.length_cons, List.take_succ_cons,
            List.map_cons, hbit, htail]

private theorem mem_zip_self {α : Type _} {l : List α} {p : α × α} (h : p ∈ l.zip l) :
    p.1 = p.2 := by
  induction l with
  | nil => simp at h
  | cons a l ih =>
      simp only [List.zip_cons_cons, List.mem_cons] at h
      rcases h with rfl | h
      · rfl
      · exact ih h

/-- **The carrier is barely disturbed**: only the last bit of a sample
can change, so the image is visually identical. -/
theorem embed_preserves_high_bits (cs : Carrier) (bs : List Bool) :
    ∀ p ∈ (embedBits cs bs).zip cs, p.1 / 2 = p.2 / 2 := by
  induction cs generalizing bs with
  | nil => cases bs <;> simp [embedBits]
  | cons c cs ih =>
      cases bs with
      | nil =>
          intro p hp
          simp only [embedBits] at hp
          rw [mem_zip_self hp]
      | cons b bs =>
          intro p hp
          simp only [embedBits, List.zip_cons_cons, List.mem_cons] at hp
          rcases hp with rfl | hp
          · cases b with
            | false => norm_num
            | true => norm_num; omega
          · exact ih bs p hp

/-- Every modified sample is still an 8-bit value. -/
theorem embed_lt_256 {cs : Carrier} (h : Carrier.valid cs) (bs : List Bool) :
    Carrier.valid (embedBits cs bs) := by
  induction cs generalizing bs with
  | nil => cases bs <;> simp [embedBits, Carrier.valid]
  | cons c cs ih =>
      cases bs with
      | nil => exact h
      | cons b bs =>
          intro v hv
          simp only [embedBits, List.mem_cons] at hv
          rcases hv with rfl | hv
          · have hc : c < 256 := h c (by simp)
            cases b <;> simp <;> omega
          · exact ih (fun w hw => h w (by simp [hw])) bs v hv

/-! ## Byte-level interface -/

/-- Hide a byte string in a carrier. -/
def embedBlob (cs : Carrier) (payload : List Nat) : Carrier :=
  embedBits cs (toBits payload)

/-- Recover `n` bytes from a carrier. -/
def extractBlob (n : Nat) (cs : Carrier) : List Nat :=
  fromBits (extractBits (8 * n) cs)

/-- Carrier capacity: one bit per sample, eight samples per byte. -/
def capacityBytes (cs : Carrier) : Nat := cs.length / 8

/-- **Covert round trip.**  A payload that fits in the carrier comes back
byte for byte. -/
theorem extractBlob_embedBlob {cs : Carrier} {payload : List Nat}
    (hp : ∀ v ∈ payload, v < 256) (hfit : 8 * payload.length ≤ cs.length) :
    extractBlob payload.length (embedBlob cs payload) = payload := by
  have hlen : (toBits payload).length = 8 * payload.length := by
    simp [toBits, List.length_flatMap, Nat.mul_comm]
  unfold extractBlob embedBlob
  rw [← hlen, extract_embed (by omega), fromBits_toBits hp]

/-! ## Reading a carrier without knowing the payload length

A meme is decoded by whoever finds it, who does not know in advance how
many bytes were hidden in it.  They therefore read the carrier to its
capacity; these lemmas say that whatever was embedded still comes back
first, followed by whatever the untouched samples happen to say. -/

/-- Reading more bits than were written still returns them, in order. -/
theorem extractBits_embedBits_prefix {cs : Carrier} {bs : List Bool} {n : Nat}
    (h : bs.length ≤ cs.length) (hn : bs.length ≤ n) :
    ∃ rest, extractBits n (embedBits cs bs) = bs ++ rest := by
  induction bs generalizing cs n with
  | nil => exact ⟨extractBits n cs, by simp [embedBits]⟩
  | cons b bs ih =>
      cases cs with
      | nil => simp at h
      | cons c cs =>
          cases n with
          | zero => simp at hn
          | succ m =>
              have h' : bs.length ≤ cs.length := by simpa using h
              have hn' : bs.length ≤ m := by simpa using hn
              obtain ⟨rest, hrest⟩ := ih h' hn'
              refine ⟨rest, ?_⟩
              have hbit : ((2 * (c / 2) + if b = true then 1 else 0) % 2 == 1) = b := by
                cases b <;> simp
              unfold extractBits at hrest ⊢
              simp only [embedBits, List.take_succ_cons, List.map_cons, hbit, hrest,
                List.cons_append]

/-- Byte reassembly reads an embedded payload off the front of a longer
bit stream. -/
theorem fromBits_toBits_append {p : List Nat} (h : ∀ v ∈ p, v < 256) (rest : List Bool) :
    fromBits (toBits p ++ rest) = p ++ fromBits rest := by
  induction p with
  | nil => simp [toBits]
  | cons b p ih =>
      have hb : b < 256 := h b (by simp)
      have hrest : ∀ v ∈ p, v < 256 := fun v hv => h v (by simp [hv])
      have hbits : byteBits b = [b / 2 ^ 7 % 2 == 1, b / 2 ^ 6 % 2 == 1, b / 2 ^ 5 % 2 == 1,
          b / 2 ^ 4 % 2 == 1, b / 2 ^ 3 % 2 == 1, b / 2 ^ 2 % 2 == 1, b / 2 ^ 1 % 2 == 1,
          b / 2 ^ 0 % 2 == 1] := by
        simp [byteBits, List.range_succ]
      rw [toBits, List.flatMap_cons, hbits]
      show bitsByte _ :: fromBits (toBits p ++ rest) = _
      rw [ih hrest, ← hbits, bitsByte_byteBits hb]
      simp

/-- **A meme can be decoded by a stranger.**  Reading a carrier to its
capacity returns the hidden payload first, whatever follows. -/
theorem extractBlob_embedBlob_prefix {cs : Carrier} {payload : List Nat} {n : Nat}
    (hp : ∀ v ∈ payload, v < 256) (hfit : 8 * payload.length ≤ cs.length)
    (hn : payload.length ≤ n) :
    ∃ rest, extractBlob n (embedBlob cs payload) = payload ++ rest := by
  have hlen : (toBits payload).length = 8 * payload.length := by
    simp [toBits, List.length_flatMap, Nat.mul_comm]
  obtain ⟨bits, hbits⟩ :=
    extractBits_embedBits_prefix (cs := cs) (bs := toBits payload) (n := 8 * n)
      (by omega) (by omega)
  exact ⟨fromBits bits, by
    unfold extractBlob embedBlob
    rw [hbits, fromBits_toBits_append hp]⟩

/-- A status update fits iff it is within the carrier's capacity. -/
theorem fits_iff_capacity (cs : Carrier) (payload : List Nat) :
    8 * payload.length ≤ cs.length ↔ payload.length ≤ cs.length / 8 := by
  omega

end Kant.Stego
