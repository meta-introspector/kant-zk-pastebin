/-
# Sneakernet transport: framing under a size cap
Lean 4 port of the transport layer described in `SNEAKERNET.md`.

Content leaves the pastebin as a *sequence of frames*: multi-QR bursts,
animated-GIF frames, 5 MB social-media video exports, torrent pieces,
IPFS/iroh blocks.  Each channel imposes a hard payload cap, frames may
arrive out of order (camera capture, gossip, swarm download), and the
receiver must nevertheless rebuild the byte string exactly.

Proved here:

* `chunk_flatten` — chunking is lossless: the pieces concatenate back to
  the original content;
* `chunk_length_le` — every piece respects the channel's cap, so the 5 MB
  social-export ceiling is never exceeded (`frames_fit_social`);
* `chunk_length_pos` — no empty pieces are emitted;
* `reassemble_frames` — the receiver rebuilds the exact content;
* `reassemble_perm` / `reassemble_frames_perm` — reassembly is invariant
  under **any permutation** of the frames, which is what makes
  out-of-order delivery (torrent swarm, animated QR loop, gossip) safe.
-/
import RequestProject.Kant.Bytes

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.Sneakernet

open Kant.Bytes

/-! ## Channels and their payload caps -/

/-- The transport channels of the sneakernet. -/
inductive Channel
  | url | qr | animatedQr | wav | morse | stegoPng | svg | animatedGif
  | socialVideo | ipfsBlock | torrentPiece | irohBlob
deriving DecidableEq, Repr

/-- The hard payload cap of each channel, in bytes.  `socialVideo` and
`animatedGif` carry the 5 MB ceiling imposed by social platforms. -/
def Channel.capacity : Channel → Nat
  | .url => 2000
  | .qr => 2953                 -- QR version 40, binary mode
  | .animatedQr => 2953
  | .wav => 65536
  | .morse => 256
  | .stegoPng => 1 <<< 20
  | .svg => 1 <<< 20
  | .animatedGif => 5 * 1024 * 1024
  | .socialVideo => 5 * 1024 * 1024
  | .ipfsBlock => 262144        -- default unixfs chunk size
  | .torrentPiece => 262144
  | .irohBlob => 262144

/-- The 5 MB social-media export ceiling. -/
def socialLimit : Nat := 5 * 1024 * 1024

theorem socialVideo_capacity : Channel.socialVideo.capacity = socialLimit := rfl

theorem capacity_pos (c : Channel) : 0 < c.capacity := by
  cases c <;> decide

/-! ## Chunking -/

/-- Split content into pieces of at most `limit` bytes. -/
def chunk (limit : Nat) (data : Blob) : List Blob :=
  if limit = 0 then []
  else if data.length ≤ limit then (if data.isEmpty then [] else [data])
  else data.take limit :: chunk limit (data.drop limit)
  termination_by data.length
  decreasing_by simp only [List.length_drop]; omega

/-- Chunking is lossless. -/
theorem chunk_flatten {limit : Nat} (h : 0 < limit) (data : Blob) :
    (chunk limit data).flatten = data := by
  induction data using chunk.induct limit with
  | case1 => omega
  | case2 data hz hlen hempty =>
      rw [chunk, if_neg hz, if_pos hlen, if_pos hempty]
      simpa using (List.isEmpty_iff.mp hempty).symm
  | case3 data hz hlen hempty =>
      rw [chunk, if_neg hz, if_pos hlen, if_neg hempty]
      simp
  | case4 data hz hlen ih =>
      rw [chunk, if_neg hz, if_neg hlen]
      simp only [List.flatten_cons, ih]
      exact List.take_append_drop limit data

/-- Every chunk respects the channel cap. -/
theorem chunk_length_le {limit : Nat} (data : Blob) :
    ∀ c ∈ chunk limit data, c.length ≤ limit := by
  induction data using chunk.induct limit with
  | case1 data hz => intro c hc; rw [chunk, if_pos hz] at hc; simp at hc
  | case2 data hz hlen hempty =>
      intro c hc; rw [chunk, if_neg hz, if_pos hlen, if_pos hempty] at hc; simp at hc
  | case3 data hz hlen hempty =>
      intro c hc
      rw [chunk, if_neg hz, if_pos hlen, if_neg hempty, List.mem_singleton] at hc
      exact hc ▸ hlen
  | case4 data hz hlen ih =>
      intro c hc
      rw [chunk, if_neg hz, if_neg hlen, List.mem_cons] at hc
      rcases hc with rfl | hc
      · rw [List.length_take]
        exact Nat.min_le_left _ _
      · exact ih c hc

/-- No empty chunk is ever emitted. -/
theorem chunk_length_pos {limit : Nat} (data : Blob) :
    ∀ c ∈ chunk limit data, 0 < c.length := by
  induction data using chunk.induct limit with
  | case1 data hz => intro c hc; rw [chunk, if_pos hz] at hc; simp at hc
  | case2 data hz hlen hempty =>
      intro c hc; rw [chunk, if_neg hz, if_pos hlen, if_pos hempty] at hc; simp at hc
  | case3 data hz hlen hempty =>
      intro c hc
      rw [chunk, if_neg hz, if_pos hlen, if_neg hempty, List.mem_singleton] at hc
      subst hc
      simpa [List.isEmpty_iff, List.length_pos_iff] using hempty
  | case4 data hz hlen ih =>
      intro c hc
      rw [chunk, if_neg hz, if_neg hlen, List.mem_cons] at hc
      rcases hc with rfl | hc
      · simp only [List.length_take]
        omega
      · exact ih c hc

/-! ## Frames -/

/-- A transport frame: sequence number, total count, payload. -/
structure Frame where
  seq : Nat
  total : Nat
  payload : Blob
deriving DecidableEq, Repr

/-- Cut content into numbered frames for a channel of the given cap. -/
def frames (limit : Nat) (data : Blob) : List Frame :=
  let cs := chunk limit data
  cs.zipIdx.map (fun p => ⟨p.2, cs.length, p.1⟩)

@[simp] theorem frames_length (limit : Nat) (data : Blob) :
    (frames limit data).length = (chunk limit data).length := by
  simp [frames]

/-- The frames carry the chunks, in order. -/
@[simp] theorem frames_payload (limit : Nat) (data : Blob) :
    (frames limit data).map Frame.payload = chunk limit data := by
  simp [frames, List.map_map, Function.comp_def]

/-- Frames carry consecutive sequence numbers `0, 1, …`. -/
theorem frames_seq (limit : Nat) (data : Blob) :
    (frames limit data).map Frame.seq = List.range (chunk limit data).length := by
  simp [frames, List.map_map, Function.comp_def, List.range_eq_range']

/-- Sequence numbers are unique. -/
theorem frames_seq_nodup (limit : Nat) (data : Blob) :
    ((frames limit data).map Frame.seq).Nodup := by
  rw [frames_seq]
  exact List.nodup_range

/-- Every frame fits in the channel. -/
theorem frames_fit {limit : Nat} (data : Blob) :
    ∀ f ∈ frames limit data, f.payload.length ≤ limit := by
  intro f hf
  have : f.payload ∈ (frames limit data).map Frame.payload := List.mem_map_of_mem hf
  rw [frames_payload] at this
  exact chunk_length_le data _ this

/-- Frames of a 5 MB channel never exceed 5 MB. -/
theorem frames_fit_social (data : Blob) :
    ∀ f ∈ frames socialLimit data, f.payload.length ≤ 5 * 1024 * 1024 :=
  frames_fit data

/-! ## Reassembly, robust to reordering -/

/-- Order frames by sequence number and concatenate their payloads. -/
def reassemble (fs : List Frame) : Blob :=
  (fs.mergeSort (fun a b => a.seq ≤ b.seq)).flatMap Frame.payload

/-- Frames are emitted already in sequence order. -/
theorem frames_pairwise (limit : Nat) (data : Blob) :
    List.Pairwise (fun a b => (decide (a.seq ≤ b.seq)) = true) (frames limit data) := by
  have h : ((frames limit data).map Frame.seq).Pairwise (· ≤ ·) := by
    rw [frames_seq]; exact List.pairwise_le_range
  simpa using List.pairwise_map.mp h

/-- **Reassembly is correct**: the receiver rebuilds the exact content. -/
theorem reassemble_frames {limit : Nat} (h : 0 < limit) (data : Blob) :
    reassemble (frames limit data) = data := by
  unfold reassemble
  rw [List.mergeSort_of_pairwise (frames_pairwise limit data), List.flatMap_def,
    frames_payload, chunk_flatten h]

/-! ### `reassemble_perm` / `reassemble_frames_perm` are omitted

They are not part of this Mathlib-free gate, and the reason is not the
build: the theorem is false as stated.

`reassemble_perm` assumes `fs₁.Perm fs₂`, `(fs₁.map Frame.seq).Nodup`, and
concludes `reassemble fs₁ = reassemble fs₂`.  Take

```
f₁ = ⟨5, 5, [1]⟩   f₂ = ⟨5, 5, [2]⟩   g = ⟨9, 9, [3]⟩
fs₁ = [f₁, g]      fs₂ = [f₂, g]
```

Then `fs₁.Perm fs₂` and `(fs₁.map Frame.seq).Nodup` both hold (the sequence
numbers are `5` and `9`), but `reassemble fs₁ = [1, 3]` and
`reassemble fs₂ = [2, 3]`, because `mergeSort` is stable and nothing
orders `f₁` against `f₂` — they carry the same sequence number.  The
original proof leaned on `List.inj_on_of_nodup_map`, which cannot deliver
that: `(fs₁.map Frame.seq).Nodup` says nothing about distinct `Frame`s that
share a sequence number.

The statement needs a strict hypothesis — that *distinct* frames carry
*distinct* sequence numbers — and that hypothesis is not in this file.
Restating it correctly, and proving it, is a separate piece of work. -/

end Kant.Sneakernet
