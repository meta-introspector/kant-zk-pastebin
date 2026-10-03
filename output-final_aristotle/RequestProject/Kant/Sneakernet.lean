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
import Mathlib
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
      · simp
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

/-- **Out-of-order delivery is safe.**  If sequence numbers are unique,
reassembly depends only on the *set* of frames received, not on the order
in which the swarm, the camera or the gossip layer delivered them. -/
theorem reassemble_perm {fs₁ fs₂ : List Frame} (hperm : fs₁.Perm fs₂)
    (hnd : (fs₁.map Frame.seq).Nodup) :
    reassemble fs₁ = reassemble fs₂ := by
  have htrans : ∀ a b c : Frame, (decide (a.seq ≤ b.seq)) = true →
      (decide (b.seq ≤ c.seq)) = true → (decide (a.seq ≤ c.seq)) = true := by
    intro a b c hab hbc
    simp only [decide_eq_true_eq] at *
    omega
  have htotal : ∀ a b : Frame, ((decide (a.seq ≤ b.seq)) || (decide (b.seq ≤ a.seq))) = true := by
    intro a b
    simp only [Bool.or_eq_true, decide_eq_true_eq]
    omega
  have hs₁ := List.pairwise_mergeSort htrans htotal fs₁
  have hs₂ := List.pairwise_mergeSort htrans htotal fs₂
  have hp : (fs₁.mergeSort (fun a b => a.seq ≤ b.seq)).Perm
      (fs₂.mergeSort (fun a b => a.seq ≤ b.seq)) :=
    ((List.mergeSort_perm fs₁ _).trans hperm).trans (List.mergeSort_perm fs₂ _).symm
  have hanti : ∀ a b : Frame, a ∈ fs₁.mergeSort (fun a b => a.seq ≤ b.seq) →
      b ∈ fs₂.mergeSort (fun a b => a.seq ≤ b.seq) →
      (decide (a.seq ≤ b.seq)) = true → (decide (b.seq ≤ a.seq)) = true → a = b := by
    intro a b ha hb hab hba
    have ha' : a ∈ fs₁ := (List.mergeSort_perm fs₁ _).mem_iff.mp ha
    have hb' : b ∈ fs₂ := (List.mergeSort_perm fs₂ _).mem_iff.mp hb
    have hb'' : b ∈ fs₁ := hperm.mem_iff.mpr hb'
    have hseq : a.seq = b.seq := by
      simp only [decide_eq_true_eq] at hab hba
      omega
    exact List.inj_on_of_nodup_map hnd ha' hb'' hseq
  unfold reassemble
  rw [List.Perm.eq_of_pairwise hanti hs₁ hs₂ hp]

/-- Correctness of reassembly for frames delivered in **any** order. -/
theorem reassemble_frames_perm {limit : Nat} (h : 0 < limit) (data : Blob)
    {fs : List Frame} (hperm : (frames limit data).Perm fs) :
    reassemble fs = data := by
  rw [← reassemble_perm hperm (frames_seq_nodup limit data), reassemble_frames h]

end Kant.Sneakernet
