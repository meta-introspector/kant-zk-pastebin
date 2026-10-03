/-
# End-to-end pipeline: paste → frames → covert carrier → peer → paste

This module composes the layers into the flow described in
`SNEAKERNET.md`:

```
content → witness/CID → frames (≤ channel cap) → stego carriers →
   any transport, any order → extract → reassemble → verify witness
```

The capstone results are `reveal_hide` (one covert frame survives) and
`pipeline_roundTrip` (the whole publication survives, whatever order the
frames arrive in), together with `pipeline_witness` — the receiver's
content hashes to the publisher's witness, which is what makes the
address self-certifying.
-/
import Mathlib
import RequestProject.Kant.Bytes
import RequestProject.Kant.Dasl
import RequestProject.Kant.Paste
import RequestProject.Kant.Sneakernet
import RequestProject.Kant.Stego

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.Pipeline

open Kant Kant.Bytes Kant.Sneakernet Kant.Stego

/-! ## Bytes as raster samples -/

/-- View a byte string as raster samples. -/
def blobToNats (b : Blob) : List Nat := b.map UInt8.toNat

/-- View raster samples as bytes. -/
def natsToBlob (l : List Nat) : Blob := l.map UInt8.ofNat

@[simp] theorem natsToBlob_blobToNats (b : Blob) : natsToBlob (blobToNats b) = b := by
  unfold natsToBlob blobToNats
  rw [List.map_map, Function.comp_def]
  simp

theorem blobToNats_lt (b : Blob) : ∀ v ∈ blobToNats b, v < 256 := by
  intro v hv
  simp only [blobToNats, List.mem_map] at hv
  obtain ⟨x, -, rfl⟩ := hv
  exact x.toNat_lt_size

@[simp] theorem blobToNats_length (b : Blob) : (blobToNats b).length = b.length := by
  simp [blobToNats]

/-! ## One covert frame -/

/-- Hide a frame's payload in a carrier image. -/
def hide (carrier : Carrier) (f : Frame) : Carrier :=
  embedBlob carrier (blobToNats f.payload)

/-- Recover `n` payload bytes from a carrier image. -/
def reveal (n : Nat) (carrier : Carrier) : Blob :=
  natsToBlob (extractBlob n carrier)

/-- **A covert frame survives.** -/
theorem reveal_hide {carrier : Carrier} {f : Frame}
    (hfit : 8 * f.payload.length ≤ carrier.length) :
    reveal f.payload.length (hide carrier f) = f.payload := by
  unfold reveal hide
  have hlen : (blobToNats f.payload).length = f.payload.length := blobToNats_length _
  rw [← hlen, extractBlob_embedBlob (blobToNats_lt f.payload) (by omega),
    natsToBlob_blobToNats]

/-- A carrier is untouched above its least significant bits. -/
theorem hide_preserves_high_bits (carrier : Carrier) (f : Frame) :
    ∀ p ∈ (hide carrier f).zip carrier, p.1 / 2 = p.2 / 2 :=
  embed_preserves_high_bits _ _

/-- A carrier stays a valid 8-bit raster. -/
theorem hide_valid {carrier : Carrier} (h : Carrier.valid carrier) (f : Frame) :
    Carrier.valid (hide carrier f) :=
  embed_lt_256 h _

/-! ## The whole publication -/

/-- Publish content on a channel of the given cap. -/
def publish (limit : Nat) (content : Blob) : List Frame := frames limit content

/-- Push one frame through a covert carrier and read it back. -/
def roundTripFrame (carrier : Carrier) (f : Frame) : Frame :=
  ⟨f.seq, f.total, reveal f.payload.length (hide carrier f)⟩

/-- A frame that fits its carrier comes back unchanged. -/
theorem roundTripFrame_eq {carrier : Carrier} {f : Frame}
    (hfit : 8 * f.payload.length ≤ carrier.length) : roundTripFrame carrier f = f := by
  unfold roundTripFrame
  rw [reveal_hide hfit]

/-- **End-to-end.**  Content published on a channel, hidden frame by
frame in carrier images, delivered in an arbitrary order by any mixture
of transports, is reconstructed exactly. -/
theorem pipeline_roundTrip {limit : Nat} (h : 0 < limit) (content : Blob)
    (carriers : Frame → Carrier) {fs : List Frame}
    (hperm : (publish limit content).Perm fs)
    (hfit : ∀ f ∈ fs, 8 * f.payload.length ≤ (carriers f).length) :
    reassemble (fs.map (fun f => roundTripFrame (carriers f) f)) = content := by
  have hmap : fs.map (fun f => roundTripFrame (carriers f) f) = fs := by
    rw [List.map_congr_left (fun f hf => roundTripFrame_eq (hfit f hf))]
    exact List.map_id fs
  rw [hmap]
  exact reassemble_frames_perm h content hperm

/-- The receiver's content is self-certifying: it hashes to the witness
the publisher advertised, and carries the same DASL address. -/
theorem pipeline_witness {limit : Nat} (h : 0 < limit) (content : Blob)
    (carriers : Frame → Carrier) {fs : List Frame}
    (hperm : (publish limit content).Perm fs)
    (hfit : ∀ f ∈ fs, 8 * f.payload.length ≤ (carriers f).length) :
    Kant.Bytes.witness (reassemble (fs.map (fun f => roundTripFrame (carriers f) f)))
        = Kant.Bytes.witness content ∧
      Kant.Dasl.nestedCid (reassemble (fs.map (fun f => roundTripFrame (carriers f) f)))
        = Kant.Dasl.nestedCid content := by
  rw [pipeline_roundTrip h content carriers hperm hfit]
  exact ⟨rfl, rfl⟩

/-- Publishing to a 5 MB channel never emits an oversized frame. -/
theorem publish_social_fits (content : Blob) :
    ∀ f ∈ publish socialLimit content, f.payload.length ≤ 5 * 1024 * 1024 :=
  frames_fit_social content

/-- The carrier capacity a publication needs: eight samples per byte. -/
theorem carrier_capacity_needed (f : Frame) (carrier : Carrier)
    (h : f.payload.length ≤ capacityBytes carrier) :
    8 * f.payload.length ≤ carrier.length := by
  unfold capacityBytes at h
  omega

end Kant.Pipeline
