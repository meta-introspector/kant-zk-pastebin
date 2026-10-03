/-
# Meme strips: one share spread over several pictures

A single picture only holds so much: a template of `n` colour samples
carries about `n/8` characters of envelope (`Kant.Meme.capacity_chars`).
A quote carries two whole posts, a page of the feed carries several, and
platforms cap what a picture may weigh.

So a large share goes out as a *strip*: the envelope is cut into numbered
parts by the sneakernet framing of `Kant.Sneakernet`, each part is hidden
in its own still — the frames of an animated GIF, a carousel, a thread of
pictures — and the reader puts them back together.  The parts carry their
own sequence numbers, so the stills may be posted, downloaded and
collected in any order.

Proved here:

* `readStrip_strip` — a strip reads back as the very envelope it was made
  from;
* `readStrip_perm` — the stills may arrive in any order at all;
* `roundTrip_post`, `roundTrip_pastes`, `roundTrip_quote_strip` — a post,
  a whole page, or a quote shipped as a strip comes back exactly;
* `strip_length`, `strip_still_length`, `strip_fits_social` — how many
  stills a share takes, and that each one is the size of the template and
  within the 5 MB social cap.
-/
import Mathlib
import RequestProject.Kant.Bytes
import RequestProject.Kant.Text
import RequestProject.Kant.Paste
import RequestProject.Kant.Sneakernet
import RequestProject.Kant.Stego
import RequestProject.Kant.Clipboard
import RequestProject.Kant.Meme
import RequestProject.Kant.Repost

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.Strip

open Kant Kant.Bytes Kant.Text Kant.Clipboard Kant.Stego Kant.Sneakernet

/-! ## One still -/

/-- Tag of one part of a strip. -/
def tagPart : Blob := asciiBytes "kzpart".toList

/-- A numbered part as an envelope: its sequence number, how many parts
there are in all, and its slice of the payload. -/
def ofFrame (f : Frame) : Envelope :=
  ⟨tagPart, [natToBytesBE f.seq, natToBytesBE f.total, f.payload]⟩

/-- Read a numbered part back. -/
def toFrame (e : Envelope) : Option Frame :=
  if e.tag ≠ tagPart then none
  else
    match e.fields with
    | [s, t, p] => some ⟨bytesBEToNat s, bytesBEToNat t, p⟩
    | _ => none

@[simp] theorem toFrame_ofFrame (f : Frame) : toFrame (ofFrame f) = some f := by
  simp only [toFrame, ofFrame, ne_eq, not_true_eq_false, if_false,
    bytesBEToNat_natToBytesBE]

/-- One still of a strip: a part hidden in the template. -/
def still (t : Kant.Meme.Template) (f : Frame) : Carrier := Kant.Meme.render t (ofFrame f)

/-- Read one still. -/
def readStill (cs : Carrier) : Option Frame := (Kant.Meme.decode cs).bind toFrame

theorem readStill_still {t : Kant.Meme.Template} {f : Frame}
    (hfit : 8 * (Kant.Meme.payload (ofFrame f)).length ≤ t.carrier.length) :
    readStill (still t f) = some f := by
  unfold readStill still
  rw [Kant.Meme.decode_render hfit]
  simp

/-! ## The strip -/

/-- Cut an envelope into parts of at most `limit` bytes each and hide one
part in each still. -/
def strip (t : Kant.Meme.Template) (limit : Nat) (e : Envelope) : List Carrier :=
  (frames limit (asciiBytes e.encode)).map (still t)

/-- Read a collection of stills. -/
def readParts : List Carrier → Option (List Frame)
  | [] => some []
  | c :: cs =>
      match readStill c, readParts cs with
      | some f, some fs => some (f :: fs)
      | _, _ => none

/-- Put a strip back together: read every still, reassemble the parts by
sequence number, and decode the envelope they spell out. -/
def readStrip (cs : List Carrier) : Option Envelope :=
  (readParts cs).bind (fun fs => Envelope.decode (asciiChars (reassemble fs)))

/-- The fitting condition: every part of the strip has room in the
template. -/
def PartsFit (t : Kant.Meme.Template) (fs : List Frame) : Prop :=
  ∀ f ∈ fs, 8 * (Kant.Meme.payload (ofFrame f)).length ≤ t.carrier.length

theorem readParts_map {t : Kant.Meme.Template} {fs : List Frame} (h : PartsFit t fs) :
    readParts (fs.map (still t)) = some fs := by
  induction fs with
  | nil => rfl
  | cons f fs ih =>
      have hf : 8 * (Kant.Meme.payload (ofFrame f)).length ≤ t.carrier.length := h f (by simp)
      have hrest : PartsFit t fs := fun g hg => h g (by simp [hg])
      simp only [List.map_cons, readParts, readStill_still hf, ih hrest]

/-- **A strip reads back as the envelope it was made from.** -/
theorem readStrip_strip {t : Kant.Meme.Template} {limit : Nat} {e : Envelope} (hlim : 0 < limit)
    (hfit : PartsFit t (frames limit (asciiBytes e.encode))) :
    readStrip (strip t limit e) = some e := by
  unfold readStrip strip
  rw [readParts_map hfit]
  simp only [Option.bind_some]
  rw [reassemble_frames hlim,
    asciiChars_asciiBytes (Envelope.isAscii_encode e), Envelope.decode_encode]

/-- **The stills may be posted, fetched or collected in any order.** -/
theorem readStrip_perm {t : Kant.Meme.Template} {limit : Nat} {e : Envelope} {fs : List Frame}
    (hlim : 0 < limit) (hperm : (frames limit (asciiBytes e.encode)).Perm fs)
    (hfit : PartsFit t fs) :
    readStrip (fs.map (still t)) = some e := by
  unfold readStrip
  rw [readParts_map hfit]
  simp only [Option.bind_some]
  rw [reassemble_frames_perm hlim _ hperm,
    asciiChars_asciiBytes (Envelope.isAscii_encode e), Envelope.decode_encode]

/-! ## What a strip costs -/

/-- A strip has one still per part. -/
@[simp] theorem strip_length (t : Kant.Meme.Template) (limit : Nat) (e : Envelope) :
    (strip t limit e).length = (chunk limit (asciiBytes e.encode)).length := by
  simp [strip]

/-- Every still is exactly the template: a strip is a set of pictures of
the same size as the one it was drawn on. -/
theorem strip_still_length (t : Kant.Meme.Template) (limit : Nat) (e : Envelope) :
    ∀ c ∈ strip t limit e, c.length = t.carrier.length := by
  intro c hc
  simp only [strip, List.mem_map] at hc
  obtain ⟨f, _, rfl⟩ := hc
  simp [still]

/-- Each still of a strip drawn on a template within the 5 MB social cap
is itself within the cap, so every picture posts anywhere. -/
theorem strip_fits_social {t : Kant.Meme.Template} (h : t.carrier.length ≤ socialLimit)
    (limit : Nat) (e : Envelope) :
    ∀ c ∈ strip t limit e, c.length ≤ 5 * 1024 * 1024 := by
  intro c hc
  rw [strip_still_length t limit e c hc]
  exact h

/-- Every still is still a valid 8-bit picture. -/
theorem strip_valid {t : Kant.Meme.Template} (h : Carrier.valid t.carrier) (limit : Nat)
    (e : Envelope) : ∀ c ∈ strip t limit e, Carrier.valid c := by
  intro c hc
  simp only [strip, List.mem_map] at hc
  obtain ⟨f, _, rfl⟩ := hc
  exact Kant.Meme.render_valid h _

/-! ## Sharing the things a reader sees -/

/-- A post as a strip. -/
def ofPaste (t : Kant.Meme.Template) (limit : Nat) (p : Paste) : List Carrier :=
  strip t limit (Kant.Clipboard.ofPaste p)

/-- A whole page of the feed as a strip. -/
def ofPastes (t : Kant.Meme.Template) (limit : Nat) (ps : List Paste) : List Carrier :=
  strip t limit (Kant.Clipboard.ofPastes ps)

/-- A quote repost as a strip. -/
def ofQuote (t : Kant.Meme.Template) (limit : Nat) (q : Kant.Repost.Quote) : List Carrier :=
  strip t limit (Kant.Repost.ofQuote q)

/-- Read a post out of a strip. -/
def toPaste (cs : List Carrier) : Option Paste := (readStrip cs).bind Kant.Clipboard.toPaste

/-- Read a page of posts out of a strip. -/
def toPastes (cs : List Carrier) : Option (List Paste) :=
  (readStrip cs).bind Kant.Clipboard.toPastes

/-- Read a quote out of a strip. -/
def toQuote (cs : List Carrier) : Option Kant.Repost.Quote :=
  (readStrip cs).bind Kant.Repost.toQuote

/-- **A post shipped as a strip of pictures comes back as the same
post.** -/
theorem roundTrip_post {t : Kant.Meme.Template} {limit : Nat} {p : Paste} (hlim : 0 < limit)
    (hc : Kant.Clipboard.Copyable p)
    (hfit : PartsFit t (frames limit (asciiBytes (Kant.Clipboard.ofPaste p).encode))) :
    toPaste (ofPaste t limit p) = some p := by
  unfold toPaste ofPaste
  rw [readStrip_strip hlim hfit]
  simpa using Kant.Clipboard.toPaste_ofPaste hc

/-- **A whole page shipped as a strip comes back post for post.** -/
theorem roundTrip_pastes {t : Kant.Meme.Template} {limit : Nat} {ps : List Paste}
    (hlim : 0 < limit) (hc : ∀ p ∈ ps, Kant.Clipboard.Copyable p)
    (hfit : PartsFit t (frames limit (asciiBytes (Kant.Clipboard.ofPastes ps).encode))) :
    toPastes (ofPastes t limit ps) = some ps := by
  unfold toPastes ofPastes
  rw [readStrip_strip hlim hfit]
  simp only [Option.bind_some, Kant.Clipboard.toPastes, Kant.Clipboard.ofPastes, ne_eq,
    not_true_eq_false, if_false, Kant.Clipboard.decodeList_ofPastes hc]

/-- **A quote shipped as a strip comes back as the same quote**, original
included. -/
theorem roundTrip_quote_strip {t : Kant.Meme.Template} {limit : Nat} {q : Kant.Repost.Quote}
    (hlim : 0 < limit) (hq : Kant.Repost.QuoteCopyable q)
    (hfit : PartsFit t (frames limit (asciiBytes (Kant.Repost.ofQuote q).encode))) :
    toQuote (ofQuote t limit q) = some q := by
  unfold toQuote ofQuote
  rw [readStrip_strip hlim hfit]
  simpa using Kant.Repost.toQuote_ofQuote hq

end Kant.Strip
