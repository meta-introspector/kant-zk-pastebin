/-
# Reposting: quotes and share cards

Seeing a post and copying it out is only half of sharing.  The other
half is *passing it on with something of your own attached*: a quote
repost, and a card that can be dropped into any social feed where the
visible text is a headline and the data rides along in the link.

Two containers are built here, both on top of the clipboard envelope of
`Kant.Clipboard`:

* a **quote** — a new post commenting on an existing one, carrying the
  quoted post whole, so the reader of the quote can check the quoted
  post themselves instead of trusting the quoter;
* a **card** — a human-readable headline followed by a share link whose
  fragment carries the entire envelope.

Proved here:

* `pasteQuote_copyQuote` — a quote copies out and pastes back as the
  same commentary on the same original;
* `pasteQuote_eq_none_of_bad_original` — a quoter cannot put words in
  someone else's mouth: a doctored quotation, whose content and witness
  disagree, fails to paste at all;
* `roundTrip_quote` — a quote fits in a meme and comes back out of it;
* `readCard_card` / `pasteCard_postCard` — a card's visible headline and
  its embedded data travel together, and the post is recovered from the
  card alone;
* `postCard_headline_no_markup` — a card can never inject markup into the
  page that displays it.
-/
import Mathlib
import RequestProject.Kant.Bytes
import RequestProject.Kant.Text
import RequestProject.Kant.Erdfa
import RequestProject.Kant.Paste
import RequestProject.Kant.Clipboard
import RequestProject.Kant.Meme

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.Repost

open Kant Kant.Bytes Kant.Text Kant.Clipboard Kant.Stego

/-! ## Quote reposts -/

/-- Tag of a quote repost. -/
def tagQuote : Blob := asciiBytes "kzquote".toList

/-- A quote repost: a post of one's own, and the post it quotes. -/
structure Quote where
  /-- The new commentary. -/
  comment : Paste
  /-- The post being quoted, carried whole. -/
  original : Paste
deriving DecidableEq, Repr

/-- Quote a post you can see in the feed. -/
def quoteWith (comment original : Paste) : Quote := ⟨comment, original⟩

/-- A quote as a copyable envelope: the clipboard text of the commentary
and the clipboard text of the original, nested without escaping because
both are pure ASCII. -/
def ofQuote (q : Quote) : Envelope :=
  ⟨tagQuote, [asciiBytes (copyText q.comment), asciiBytes (copyText q.original)]⟩

/-- Read a quote back out of an envelope.  Both halves must themselves
paste — in particular the original must match its own witness. -/
def toQuote (e : Envelope) : Option Quote :=
  if e.tag ≠ tagQuote then none
  else
    match e.fields with
    | [c, o] =>
        match pasteText (asciiChars c), pasteText (asciiChars o) with
        | some cp, some op => some ⟨cp, op⟩
        | _, _ => none
    | _ => none

/-- The clipboard text of a quote. -/
def copyQuote (q : Quote) : List Char := (ofQuote q).encode

/-- Paste clipboard text back into a quote. -/
def pasteQuote (s : List Char) : Option Quote := (Envelope.decode s).bind toQuote

/-- Both halves of a quote must be copyable for the quote to be. -/
structure QuoteCopyable (q : Quote) : Prop where
  /-- The commentary is copyable. -/
  comment : Copyable q.comment
  /-- The quoted post is copyable. -/
  original : Copyable q.original

theorem toQuote_ofQuote {q : Quote} (h : QuoteCopyable q) : toQuote (ofQuote q) = some q := by
  have hc : asciiChars (asciiBytes (copyText q.comment)) = copyText q.comment :=
    asciiChars_asciiBytes (Envelope.isAscii_encode _)
  have ho : asciiChars (asciiBytes (copyText q.original)) = copyText q.original :=
    asciiChars_asciiBytes (Envelope.isAscii_encode _)
  simp only [toQuote, ofQuote, ne_eq, not_true_eq_false, if_false, hc, ho,
    pasteText_copyText h.comment, pasteText_copyText h.original]

/-- **A quote survives copy and paste**: the commentary and the quoted
post both come back exactly. -/
theorem pasteQuote_copyQuote {q : Quote} (h : QuoteCopyable q) :
    pasteQuote (copyQuote q) = some q := by
  unfold pasteQuote copyQuote
  rw [Envelope.decode_encode]
  simpa using toQuote_ofQuote h

/-- **A quotation cannot be doctored.**  If the quoted half does not
paste — because its content and its witness disagree — the whole quote is
rejected rather than shown with a fabricated original. -/
theorem pasteQuote_eq_none_of_bad_original {s : List Char} {c o : Blob}
    (hs : Envelope.decode s = some ⟨tagQuote, [c, o]⟩)
    (ho : pasteText (asciiChars o) = none) : pasteQuote s = none := by
  simp only [pasteQuote, hs, Option.bind_some, toQuote, ne_eq, not_true_eq_false, if_false, ho]
  cases pasteText (asciiChars c) <;> rfl

/-- Reading a quote gives back exactly the post that was quoted. -/
theorem quoted_original {comment original : Paste}
    (h : QuoteCopyable (quoteWith comment original)) :
    ((pasteQuote (copyQuote (quoteWith comment original))).map Quote.original)
      = some original := by
  rw [pasteQuote_copyQuote h]
  rfl

/-! ## A quote as a meme

Because a quote is an ordinary envelope it goes straight into the meme
container of `Kant.Meme`: one picture that carries both the commentary
and the post it is about. -/

/-- A meme carrying a quote repost. -/
def memeOfQuote (t : Kant.Meme.Template) (q : Quote) : Carrier :=
  Kant.Meme.render t (ofQuote q)

/-- Read a quote out of a meme. -/
def memeToQuote (cs : Carrier) : Option Quote := (Kant.Meme.decode cs).bind toQuote

/-- **A quote shared as a picture comes back as the same quote.** -/
theorem roundTrip_quote {t : Kant.Meme.Template} {q : Quote} (hq : QuoteCopyable q)
    (hfit : 8 * (Kant.Meme.payload (ofQuote q)).length ≤ t.carrier.length) :
    memeToQuote (memeOfQuote t q) = some q := by
  unfold memeToQuote memeOfQuote
  rw [Kant.Meme.decode_render hfit]
  simpa using toQuote_ofQuote hq

/-! ## Share cards

A card is what gets pasted into a chat window or a social post: a line of
readable text, then a link.  Everything after the first `'#'` is the
envelope, so the data survives even when the surrounding text is edited,
and the headline is `'#'`-free by construction. -/

/-- Strip the fragment marker from a headline so that the link's `'#'` is
the first one in the card. -/
def sanitize (s : List Char) : List Char := s.filter (fun c => c ≠ hash)

theorem hash_not_mem_sanitize (s : List Char) : hash ∉ sanitize s := by
  intro h
  simp only [sanitize, List.mem_filter, decide_eq_true_eq] at h
  exact h.2 rfl

theorem sanitize_sublist (s : List Char) : (sanitize s).Sublist s := List.filter_sublist

@[simp] theorem sanitize_idem (s : List Char) : sanitize (sanitize s) = sanitize s := by
  simp [sanitize, List.filter_filter]

/-- A share card: a headline, a newline, and a link carrying the data. -/
def card (headline base : List Char) (e : Envelope) : List Char :=
  sanitize headline ++ '\n' :: shareUrl base e

/-- Recover the envelope from a card: everything after its first `'#'`. -/
def readCard (s : List Char) : Option Envelope := parseShareUrl s

/-- **The visible text and the embedded data travel together.** -/
theorem readCard_card {headline base : List Char} (hb : hash ∉ base) (e : Envelope) :
    readCard (card headline base e) = some e := by
  have hcard : card headline base e
      = (sanitize headline ++ '\n' :: base) ++ hash :: e.encode := by
    simp [card, shareUrl]
  have hne : hash ∉ sanitize headline ++ '\n' :: base := by
    simp only [List.mem_append, List.mem_cons, not_or]
    refine ⟨hash_not_mem_sanitize headline, ?_, hb⟩
    decide
  unfold readCard parseShareUrl
  rw [hcard, fragment_append hne, Envelope.decode_encode]

/-- The headline shown for a post: its escaped title and its address. -/
def headline (p : Paste) : List Char :=
  sanitize (Kant.Erdfa.escape (p.title ++ ' ' :: p.witness))

/-- A card for a post. -/
def postCard (base : List Char) (p : Paste) : List Char :=
  card (headline p) base (ofPaste p)

/-- A card for the numeric results of a publish. -/
def receiptCard (base : List Char) (r : Receipt) : List Char :=
  card (sanitize r.witness) base (ofReceipt r)

/-- A card for everything on a page of the feed. -/
def bundleCard (base : List Char) (ps : List Paste) : List Char :=
  card (sanitize (toString ps.length).toList) base (ofPastes ps)

/-- **A post pasted from a card is the same post.** -/
theorem pasteCard_postCard {base : List Char} (hb : hash ∉ base) {p : Paste}
    (h : Copyable p) : ((readCard (postCard base p)).bind toPaste) = some p := by
  unfold postCard
  rw [readCard_card hb]
  simpa using toPaste_ofPaste h

/-- **Results pasted from a card are the same results.** -/
theorem pasteCard_receiptCard {base : List Char} (hb : hash ∉ base) {r : Receipt}
    (hw : IsAscii r.witness) : ((readCard (receiptCard base r)).bind toReceipt) = some r := by
  unfold receiptCard
  rw [readCard_card hb]
  simp only [Option.bind_some, toReceipt, ofReceipt, ne_eq, not_true_eq_false, if_false,
    asciiChars_asciiBytes hw, bytesBEToNat_natToBytesBE]

/-- **A whole page pasted from a card is the same page.** -/
theorem pasteCard_bundleCard {base : List Char} (hb : hash ∉ base) {ps : List Paste}
    (h : ∀ p ∈ ps, Copyable p) : ((readCard (bundleCard base ps)).bind toPastes) = some ps := by
  unfold bundleCard
  rw [readCard_card hb]
  simp only [Option.bind_some, toPastes, ofPastes, ne_eq, not_true_eq_false, if_false,
    decodeList_ofPastes h]

/-- **A card can never inject markup** into the page that displays it. -/
theorem postCard_headline_no_markup (p : Paste) :
    '<' ∉ headline p ∧ '>' ∉ headline p ∧ '"' ∉ headline p := by
  obtain ⟨h1, h2, h3⟩ := Kant.Erdfa.escape_no_markup (p.title ++ ' ' :: p.witness)
  refine ⟨?_, ?_, ?_⟩ <;> intro hc <;>
    exact absurd ((sanitize_sublist _).mem hc) (by assumption)

/-- The headline of a card is readable text: the title and address of the
post can be recovered from what the reader sees. -/
theorem headline_recoverable {p : Paste} (h : hash ∉ Kant.Erdfa.escape (p.title ++ ' ' :: p.witness)) :
    Kant.Erdfa.unescape (headline p) = p.title ++ ' ' :: p.witness := by
  have : sanitize (Kant.Erdfa.escape (p.title ++ ' ' :: p.witness))
      = Kant.Erdfa.escape (p.title ++ ' ' :: p.witness) := by
    refine List.filter_eq_self.2 ?_
    intro c hc
    simp only [decide_eq_true_eq]
    rintro rfl
    exact h hc
  rw [headline, this, Kant.Erdfa.escape_unescape_id]

/-- The address of the post is always visible on the card itself. -/
theorem card_shows_address {base : List Char} (p : Paste) :
    (headline p) <:+: postCard base p :=
  ⟨[], '\n' :: shareUrl base (ofPaste p), by simp [postCard, card, headline]⟩

end Kant.Repost
