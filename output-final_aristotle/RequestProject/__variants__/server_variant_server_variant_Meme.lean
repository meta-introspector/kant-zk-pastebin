/-
# Memes with embedded data

A meme is a picture with two lines of text on it — and, hidden in the
least significant bits of its pixels, the entire post it is about.  It
can be posted to any platform that carries images; anyone who saves the
file gets the data back, exactly, with no server involved.

The payload is the clipboard envelope of `Kant.Clipboard`, prefixed with
a magic marker and terminated by a zero byte.  Since the envelope is
printable ASCII it never contains a zero byte itself, so the terminator
is unambiguous and a finder who does not know the payload length can
still read it: they read the carrier to its capacity and stop at the
first zero (`Kant.Stego.extractBlob_embedBlob_prefix`).

Proved here:

* `decode_render` — whatever is embedded comes back out, and only the
  intended marker is accepted;
* `roundTrip_paste` — a post shared as a meme is recovered as exactly
  that post, addresses and all;
* `roundTrip_receipt` — the same for the numeric results of a publish;
* `render_length`, `render_valid`, `render_preserves_high_bits` — the
  meme is the same size and the same picture as the template, up to one
  unit per sample;
* `fits_social` — a meme built on a template within the 5 MB social cap
  is itself within the cap, so it can be posted anywhere;
* `capacity_chars` — exactly how much text a template can carry;
* `caption_no_markup` / `caption_recoverable` — the visible caption is
  safe to put in a page and still readable back.
-/
import Mathlib
import RequestProject.Kant.Bytes
import RequestProject.Kant.Text
import RequestProject.Kant.Erdfa
import RequestProject.Kant.Paste
import RequestProject.Kant.Clipboard
import RequestProject.Kant.Stego
import RequestProject.Kant.Sneakernet

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.Meme

open Kant Kant.Bytes Kant.Text Kant.Clipboard Kant.Stego

/-! ## The template -/

/-- A meme template: a picture and the two lines of text drawn on it. -/
structure Template where
  /-- The line drawn across the top. -/
  topText : List Char
  /-- The line drawn across the bottom. -/
  bottomText : List Char
  /-- The picture, one 8-bit sample per entry. -/
  carrier : Carrier
deriving Repr

/-- The marker every embedded payload starts with. -/
def magic : List Char := ['K', 'Z', 'M', '1']

/-- The payload embedded in a meme: marker, envelope, zero terminator. -/
def payload (e : Envelope) : List Nat := charCodes (magic ++ e.encode) ++ [0]

/-- Draw the meme: hide the payload in the least significant bits. -/
def render (t : Template) (e : Envelope) : Carrier := embedBlob t.carrier (payload e)

/-- Read the hidden bytes of a carrier: everything up to the first zero. -/
def readPayload (cs : Carrier) : List Nat :=
  (extractBlob (capacityBytes cs) cs).takeWhile (fun v => !(v == 0))

/-- Recover the envelope hidden in a picture, if there is one. -/
def decode (cs : Carrier) : Option Envelope :=
  let text := codeChars (readPayload cs)
  if magic.isPrefixOf text then Envelope.decode (text.drop magic.length) else none

/-! ## Basic facts about the payload -/

theorem magic_ascii : IsAscii magic := by
  intro c hc
  simp only [magic, List.mem_cons, List.not_mem_nil, or_false] at hc
  rcases hc with rfl | rfl | rfl | rfl <;> decide

theorem magic_pos : ∀ c ∈ magic, 0 < c.toNat := by
  intro c hc
  simp only [magic, List.mem_cons, List.not_mem_nil, or_false] at hc
  rcases hc with rfl | rfl | rfl | rfl <;> decide

theorem payload_ascii (e : Envelope) : IsAscii (magic ++ e.encode) := by
  intro c hc
  rcases List.mem_append.mp hc with h | h
  · exact magic_ascii c h
  · exact Envelope.isAscii_encode e c h

theorem payload_lt_256 (e : Envelope) : ∀ v ∈ payload e, v < 256 := by
  intro v hv
  rcases List.mem_append.mp hv with h | h
  · exact charCodes_lt_256 (payload_ascii e) v h
  · simp only [List.mem_singleton] at h; omega

theorem payload_head_ne_zero (e : Envelope) : ∀ v ∈ charCodes (magic ++ e.encode), v ≠ 0 := by
  refine charCodes_ne_zero ?_
  intro c hc
  rcases List.mem_append.mp hc with h | h
  · exact magic_pos c h
  · exact Envelope.encode_pos e c h

@[simp] theorem payload_length (e : Envelope) :
    (payload e).length = magic.length + e.encode.length + 1 := by
  simp [payload]
  omega

/-- Reading stops at the terminator. -/
theorem takeWhile_append_zero {l rest : List Nat} (h : ∀ v ∈ l, v ≠ 0) :
    (l ++ 0 :: rest).takeWhile (fun v => !(v == 0)) = l := by
  induction l with
  | nil => simp
  | cons a l ih =>
      have ha : a ≠ 0 := h a (by simp)
      have hrest : ∀ v ∈ l, v ≠ 0 := fun v hv => h v (by simp [hv])
      simp [ha, ih hrest]

/-! ## The picture is undamaged -/

/-- A meme has exactly as many samples as its template. -/
@[simp] theorem render_length (t : Template) (e : Envelope) :
    (render t e).length = t.carrier.length := by
  simp [render, embedBlob]

/-- The meme is still a valid 8-bit picture. -/
theorem render_valid {t : Template} (h : Carrier.valid t.carrier) (e : Envelope) :
    Carrier.valid (render t e) := embed_lt_256 h _

/-- Only the bottom bit of any sample changes: the meme looks like the
template. -/
theorem render_preserves_high_bits (t : Template) (e : Envelope) :
    ∀ p ∈ (render t e).zip t.carrier, p.1 / 2 = p.2 / 2 :=
  embed_preserves_high_bits _ _

/-- A meme built on a template that a platform accepts is itself
acceptable: embedding data does not grow the file. -/
theorem fits_social {t : Template} (h : t.carrier.length ≤ Kant.Sneakernet.socialLimit)
    (e : Envelope) : (render t e).length ≤ 5 * 1024 * 1024 := by
  rw [render_length]
  exact h

/-- How many characters of envelope a template can carry. -/
def capacityChars (t : Template) : Nat := capacityBytes t.carrier - magic.length - 1

/-- The payload fits exactly when the envelope is within the template's
character capacity. -/
theorem capacity_chars (t : Template) (e : Envelope) :
    8 * (payload e).length ≤ t.carrier.length ↔
      magic.length + e.encode.length + 1 ≤ capacityBytes t.carrier := by
  rw [payload_length]
  unfold capacityBytes
  omega

/-! ## The data survives -/

/-- **What goes into a meme comes back out.** -/
theorem decode_render {t : Template} {e : Envelope}
    (hfit : 8 * (payload e).length ≤ t.carrier.length) : decode (render t e) = some e := by
  have hcap : (payload e).length ≤ capacityBytes (render t e) := by
    rw [capacityBytes, render_length]
    omega
  obtain ⟨rest, hrest⟩ :=
    extractBlob_embedBlob_prefix (cs := t.carrier) (payload := payload e)
      (n := capacityBytes (render t e)) (payload_lt_256 e) (by omega) hcap
  rw [show embedBlob t.carrier (payload e) = render t e from rfl] at hrest
  have hread : readPayload (render t e) = charCodes (magic ++ e.encode) := by
    unfold readPayload
    rw [hrest]
    have : payload e ++ rest = charCodes (magic ++ e.encode) ++ 0 :: rest := by
      simp [payload]
    rw [this, takeWhile_append_zero (payload_head_ne_zero e)]
  have htext : codeChars (readPayload (render t e)) = magic ++ e.encode := by
    rw [hread, codeChars_charCodes]
  unfold decode
  simp only [htext, List.isPrefixOf_iff_prefix.mpr ⟨e.encode, rfl⟩, if_true,
    List.drop_left' rfl]
  exact Envelope.decode_encode e

/-! ## Sharing a post -/

/-- Share a post as a meme. -/
def ofPaste (t : Template) (p : Paste) : Carrier := render t (Kant.Clipboard.ofPaste p)

/-- Share the numeric results of a publish as a meme. -/
def ofReceipt (t : Template) (r : Receipt) : Carrier := render t (Kant.Clipboard.ofReceipt r)

/-- Recover a post from a meme. -/
def toPaste (cs : Carrier) : Option Paste := (decode cs).bind Kant.Clipboard.toPaste

/-- Recover a result summary from a meme. -/
def toReceipt (cs : Carrier) : Option Receipt := (decode cs).bind Kant.Clipboard.toReceipt

/-- **A post shared as a meme is recovered as that post.** -/
theorem roundTrip_paste {t : Template} {p : Paste} (hc : Kant.Clipboard.Copyable p)
    (hfit : 8 * (payload (Kant.Clipboard.ofPaste p)).length ≤ t.carrier.length) :
    toPaste (ofPaste t p) = some p := by
  unfold toPaste ofPaste
  rw [decode_render hfit]
  simpa using Kant.Clipboard.toPaste_ofPaste hc

/-- **The results shared as a meme are recovered exactly.** -/
theorem roundTrip_receipt {t : Template} {r : Receipt} (hw : IsAscii r.witness)
    (hfit : 8 * (payload (Kant.Clipboard.ofReceipt r)).length ≤ t.carrier.length) :
    toReceipt (ofReceipt t r) = some r := by
  unfold toReceipt ofReceipt
  rw [decode_render hfit]
  simp only [Option.bind_some, Kant.Clipboard.toReceipt, Kant.Clipboard.ofReceipt, ne_eq,
    not_true_eq_false, if_false, asciiChars_asciiBytes hw, bytesBEToNat_natToBytesBE]

/-- **The results of a publish always share losslessly.** -/
theorem roundTrip_receiptOf {t : Template} (p : Paste) (credits : Nat)
    (hfit : 8 * (payload (Kant.Clipboard.ofReceipt (receiptOf p credits))).length ≤
      t.carrier.length) :
    toReceipt (ofReceipt t (receiptOf p credits)) = some (receiptOf p credits) :=
  roundTrip_receipt (Kant.Clipboard.isAscii_receiptOf_witness p credits) hfit

/-! ## Sharing a whole page -/

/-- Share several posts — a thread, a page of the feed, a search result —
as one meme. -/
def ofPastes (t : Template) (ps : List Paste) : Carrier :=
  render t (Kant.Clipboard.ofPastes ps)

/-- Recover a whole page of posts from a meme. -/
def toPastes (cs : Carrier) : Option (List Paste) := (decode cs).bind Kant.Clipboard.toPastes

/-- **A page of the feed shared as a meme comes back post for post.** -/
theorem roundTrip_pastes {t : Template} {ps : List Paste}
    (hc : ∀ p ∈ ps, Kant.Clipboard.Copyable p)
    (hfit : 8 * (payload (Kant.Clipboard.ofPastes ps)).length ≤ t.carrier.length) :
    toPastes (ofPastes t ps) = some ps := by
  unfold toPastes ofPastes
  rw [decode_render hfit]
  simp only [Option.bind_some, Kant.Clipboard.toPastes, Kant.Clipboard.ofPastes, ne_eq,
    not_true_eq_false, if_false, Kant.Clipboard.decodeList_ofPastes hc]

/-! ## The visible caption

The caption is what a reader sees without extracting anything: the two
lines of the template plus the address of the post.  It is escaped, so
putting a meme in a page cannot inject markup, and it is recoverable, so
a reader can still read the exact text. -/

/-- The caption of a meme about a post. -/
def caption (t : Template) (p : Paste) : List Char :=
  Kant.Erdfa.escape (t.topText ++ p.witness ++ t.bottomText)

/-- A caption can never break out of its element. -/
theorem caption_no_markup (t : Template) (p : Paste) :
    '<' ∉ caption t p ∧ '>' ∉ caption t p ∧ '"' ∉ caption t p :=
  Kant.Erdfa.escape_no_markup _

/-- The caption is losslessly readable. -/
theorem caption_recoverable (t : Template) (p : Paste) :
    Kant.Erdfa.unescape (caption t p) = t.topText ++ p.witness ++ t.bottomText :=
  Kant.Erdfa.escape_unescape_id _

/-- The address is always visible on the meme itself, not only hidden in
it. -/
theorem witness_infix_caption (t : Template) (p : Paste) :
    p.witness <:+: Kant.Erdfa.unescape (caption t p) := by
  rw [caption_recoverable]
  exact ⟨t.topText, t.bottomText, by simp⟩

/-! ## Posting a meme

A meme leaves as an ordinary image file, so it travels over the
sneakernet channels of `Kant.Sneakernet` like any other blob. -/

/-- The bytes of a meme, ready to be framed for a channel. -/
def bytes (cs : Carrier) : Blob := cs.map (fun v => UInt8.ofNat v)

/-- Every frame of a posted meme respects the 5 MB social cap. -/
theorem frames_fit_social (cs : Carrier) :
    ∀ f ∈ Kant.Sneakernet.frames Kant.Sneakernet.socialLimit (bytes cs),
      f.payload.length ≤ 5 * 1024 * 1024 :=
  Kant.Sneakernet.frames_fit_social _

/-- A posted meme is reassembled from its frames in any order. -/
theorem post_roundTrip (cs : Carrier) {fs : List Kant.Sneakernet.Frame}
    (h : (Kant.Sneakernet.frames Kant.Sneakernet.socialLimit (bytes cs)).Perm fs) :
    Kant.Sneakernet.reassemble fs = bytes cs :=
  Kant.Sneakernet.reassemble_frames_perm (by decide) _ h

end Kant.Meme
