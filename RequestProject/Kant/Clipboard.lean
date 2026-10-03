/-
# Copy and paste: a self-verifying clipboard envelope

Everything the reader can see in the feed can also be *copied out* as one
line of plain text and *pasted back* — into another tab, another peer's
client, a chat window, an issue tracker — with no loss and no ambiguity.

The envelope is a tag plus a list of byte fields, each hex encoded and
joined with `':'` (`Kant.Text`).  Because hex never produces a colon, the
framing is unambiguous, and because the encoding is pure ASCII the result
travels through any channel that carries characters.

Proved here:

* `Envelope.decode_encode` — copy then paste returns the very same
  envelope;
* `pasteText_copyText` — a post copied out of the feed pastes back as the
  same post, addresses and all;
* `pasteText_certified` — a pasted post is accepted only if the witness
  travelling with it is the witness of the content that arrived, so a
  tampered clipboard string is rejected rather than silently trusted;
* `pasteReceipt_copyReceipt` — the numeric results of a publish (address,
  size, credits earned) copy and paste back exactly;
* `parseShareUrl_shareUrl` — the same envelope can travel as the fragment
  of a URL that can be pasted into any address bar.
-/
import Mathlib
import RequestProject.Kant.Bytes
import RequestProject.Kant.Text
import RequestProject.Kant.Paste

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.Clipboard

open Kant Kant.Bytes Kant.Text

/-! ## The envelope -/

/-- A copyable result: a tag naming the kind of result, and its fields. -/
structure Envelope where
  /-- What kind of result this is (`kzpaste`, `kzresult`, …). -/
  tag : Blob
  /-- The payload fields, in a tag-specific order. -/
  fields : List Blob
deriving DecidableEq, Repr

namespace Envelope

/-- Render an envelope as one line of text. -/
def encode (e : Envelope) : List Char :=
  joinFields ((e.tag :: e.fields).map hexEncode)

/-- Decode a list of hex fields. -/
def decodeAll : List (List Char) → Option (List Blob)
  | [] => some []
  | f :: fs =>
      match hexDecode f, decodeAll fs with
      | some b, some bs => some (b :: bs)
      | _, _ => none

/-- Parse a line of text back into an envelope. -/
def decode (s : List Char) : Option Envelope :=
  match splitFields s with
  | [] => none
  | t :: fs =>
      match hexDecode t, decodeAll fs with
      | some tag, some fields => some ⟨tag, fields⟩
      | _, _ => none

theorem decodeAll_map_hexEncode (bss : List Blob) :
    decodeAll (bss.map hexEncode) = some bss := by
  induction bss with
  | nil => rfl
  | cons b bs ih => simp [decodeAll, hexDecode_hexEncode, ih]

/-- **Copy then paste is the identity.** -/
theorem decode_encode (e : Envelope) : decode e.encode = some e := by
  have hsep : ∀ f ∈ (e.tag :: e.fields).map hexEncode, sep ∉ f := by
    intro f hf
    simp only [List.mem_map] at hf
    obtain ⟨b, _, rfl⟩ := hf
    exact sep_not_mem_hexEncode b
  have hne : (e.tag :: e.fields).map hexEncode ≠ [] := by simp
  unfold decode encode
  rw [splitFields_joinFields hne hsep]
  simp only [List.map_cons, hexDecode_hexEncode, decodeAll_map_hexEncode]

/-- Copied text is plain ASCII, so it survives any text channel. -/
theorem isAscii_encode (e : Envelope) : IsAscii e.encode := by
  refine isAscii_joinFields ?_
  intro f hf
  simp only [List.mem_map] at hf
  obtain ⟨b, _, rfl⟩ := hf
  exact isAscii_hexEncode b

/-- Copied text never contains a NUL, which is what lets the meme
exporter terminate an embedded payload with a zero byte. -/
theorem encode_pos (e : Envelope) : ∀ c ∈ e.encode, 0 < c.toNat := by
  refine joinFields_pos ?_
  intro f hf
  simp only [List.mem_map] at hf
  obtain ⟨b, _, rfl⟩ := hf
  exact hexEncode_pos b

end Envelope

/-! ## Copying a post -/

/-- Tag of a copied post. -/
def tagPaste : Blob := asciiBytes "kzpaste".toList

/-- Tag of a copied result summary. -/
def tagReceipt : Blob := asciiBytes "kzresult".toList

/-- An optional string field: a leading `0` for `none`, `1` for `some`. -/
def optField : Option (List Char) → Blob
  | none => [0]
  | some s => 1 :: asciiBytes s

/-- Read an optional string field back. -/
def parseOptField : Blob → Option (Option (List Char))
  | [0] => some none
  | 1 :: bs => some (some (asciiChars bs))
  | _ => none

theorem parseOptField_optField {o : Option (List Char)}
    (h : ∀ s, o = some s → IsAscii s) : parseOptField (optField o) = some o := by
  cases o with
  | none => rfl
  | some s =>
      have hs : IsAscii s := h s rfl
      cases s with
      | nil => rfl
      | cons c cs =>
          have hround := asciiChars_asciiBytes hs
          simp only [optField, parseOptField]
          rw [hround]

/-- A post as a copyable envelope: identifier, title, content, timestamp,
thread parent and the witness that certifies the content. -/
def ofPaste (p : Paste) : Envelope :=
  ⟨tagPaste,
    [asciiBytes p.id, asciiBytes p.title, p.content, asciiBytes p.timestamp,
     optField p.replyTo, asciiBytes p.witness]⟩

/-- Read a post back out of an envelope.  The post is accepted only if
the witness that arrived is the witness of the content that arrived. -/
def toPaste (e : Envelope) : Option Paste :=
  if e.tag ≠ tagPaste then none
  else
    match e.fields with
    | [i, t, c, ts, r, w] =>
        match parseOptField r with
        | none => none
        | some rep =>
            let p : Paste := ⟨asciiChars i, asciiChars t, c, asciiChars ts, rep⟩
            if p.witness = asciiChars w then some p else none
    | _ => none

/-- The fields of a post that must be ASCII for it to be copyable. -/
structure Copyable (p : Paste) : Prop where
  /-- The identifier is ASCII. -/
  id : IsAscii p.id
  /-- The title is ASCII. -/
  title : IsAscii p.title
  /-- The timestamp is ASCII. -/
  timestamp : IsAscii p.timestamp
  /-- The thread parent, if any, is ASCII. -/
  replyTo : ∀ s, p.replyTo = some s → IsAscii s

/-- **A post survives copy and paste.** -/
theorem toPaste_ofPaste {p : Paste} (h : Copyable p) : toPaste (ofPaste p) = some p := by
  have hwa : IsAscii p.witness := isAscii_hexEncode (Kant.Bytes.digest p.content)
  have hw : asciiChars (asciiBytes p.witness) = p.witness := asciiChars_asciiBytes hwa
  simp only [toPaste, ofPaste, ne_eq, not_true_eq_false, if_false,
    parseOptField_optField h.replyTo, asciiChars_asciiBytes h.id,
    asciiChars_asciiBytes h.title, asciiChars_asciiBytes h.timestamp, hw]
  rfl

/-- **Tampering is detected.**  If the content and the witness of a
clipboard string disagree, pasting fails instead of quietly accepting a
mislabelled post. -/
theorem toPaste_eq_none_of_mismatch {i t c ts r w : Blob}
    (h : Kant.Bytes.witness c ≠ asciiChars w) :
    toPaste ⟨tagPaste, [i, t, c, ts, r, w]⟩ = none := by
  simp only [toPaste, ne_eq, not_true_eq_false, if_false]
  cases hr : parseOptField r with
  | none => rfl
  | some rep => simpa [Paste.witness] using h

/-- A pasted post carries exactly the witness field that was transmitted. -/
theorem toPaste_witness_field {i t c ts r w : Blob} {p : Paste}
    (h : toPaste ⟨tagPaste, [i, t, c, ts, r, w]⟩ = some p) :
    p.witness = asciiChars w := by
  simp only [toPaste, ne_eq, not_true_eq_false, if_false] at h
  cases hr : parseOptField r with
  | none => rw [hr] at h; exact absurd h (by simp)
  | some rep =>
      rw [hr] at h
      by_cases hw : (⟨asciiChars i, asciiChars t, c, asciiChars ts, rep⟩ : Paste).witness =
          asciiChars w
      · simp only [hw, if_true, Option.some.injEq] at h
        rw [← h]
        exact hw
      · simp only [hw, if_false] at h
        exact absurd h (by simp)

/-- The clipboard text of a post. -/
def copyText (p : Paste) : List Char := (ofPaste p).encode

/-- Paste clipboard text back into a post. -/
def pasteText (s : List Char) : Option Paste := (Envelope.decode s).bind toPaste

/-- **Copy a post, paste it back, get the same post.** -/
theorem pasteText_copyText {p : Paste} (h : Copyable p) : pasteText (copyText p) = some p := by
  unfold pasteText copyText
  rw [Envelope.decode_encode]
  simpa using toPaste_ofPaste h

/-- Pasting text whose content and witness disagree fails. -/
theorem pasteText_eq_none_of_mismatch {s : List Char} {i t c ts r w : Blob}
    (hs : Envelope.decode s = some ⟨tagPaste, [i, t, c, ts, r, w]⟩)
    (h : Kant.Bytes.witness c ≠ asciiChars w) : pasteText s = none := by
  simp [pasteText, hs, toPaste_eq_none_of_mismatch h]

/-! ## Copying a whole page of the feed

A reader can also take *everything they can see* in one go: a bundle is
an envelope whose fields are the clipboard texts of the individual
posts.  Since those texts are themselves ASCII, they nest without any
further escaping. -/

/-- Tag of a copied bundle of posts. -/
def tagBundle : Blob := asciiBytes "kzfeed".toList

/-- Several posts as one copyable envelope. -/
def ofPastes (ps : List Paste) : Envelope :=
  ⟨tagBundle, ps.map (fun p => asciiBytes (copyText p))⟩

/-- Read a list of posts back out of the fields of a bundle. -/
def decodeList : List Blob → Option (List Paste)
  | [] => some []
  | f :: fs =>
      match pasteText (asciiChars f), decodeList fs with
      | some p, some rest => some (p :: rest)
      | _, _ => none

/-- Read a bundle of posts. -/
def toPastes (e : Envelope) : Option (List Paste) :=
  if e.tag ≠ tagBundle then none else decodeList e.fields

/-- The clipboard text of everything on screen. -/
def copyAll (ps : List Paste) : List Char := (ofPastes ps).encode

/-- Paste a whole bundle back. -/
def pasteAll (s : List Char) : Option (List Paste) := (Envelope.decode s).bind toPastes

theorem decodeList_ofPastes {ps : List Paste} (h : ∀ p ∈ ps, Copyable p) :
    decodeList (ps.map (fun p => asciiBytes (copyText p))) = some ps := by
  induction ps with
  | nil => rfl
  | cons p ps ih =>
      have hp : Copyable p := h p (by simp)
      have hrest : ∀ q ∈ ps, Copyable q := fun q hq => h q (by simp [hq])
      have hascii : asciiChars (asciiBytes (copyText p)) = copyText p :=
        asciiChars_asciiBytes (Envelope.isAscii_encode _)
      simp only [List.map_cons, decodeList, hascii, pasteText_copyText hp, ih hrest]

/-- **A whole page of the feed copies and pastes back post for post.** -/
theorem pasteAll_copyAll {ps : List Paste} (h : ∀ p ∈ ps, Copyable p) :
    pasteAll (copyAll ps) = some ps := by
  unfold pasteAll copyAll
  rw [Envelope.decode_encode]
  simp only [Option.bind_some, toPastes, ofPastes, ne_eq, not_true_eq_false, if_false,
    decodeList_ofPastes h]

/-! ## Copying the results of a publish -/

/-- The numeric summary shown next to a post: its address, its size and
the credits its owner has earned serving it. -/
structure Receipt where
  /-- The 64-character content witness. -/
  witness : List Char
  /-- The DASL content address. -/
  cid : Nat
  /-- The size of the content in bytes. -/
  bytes : Nat
  /-- Credits earned so far for serving it. -/
  credits : Nat
deriving DecidableEq, Repr

/-- The receipt of a post, given the credits earned for it. -/
def receiptOf (p : Paste) (credits : Nat) : Receipt :=
  ⟨p.witness, p.cid, p.content.length, credits⟩

/-- A receipt as a copyable envelope. -/
def ofReceipt (r : Receipt) : Envelope :=
  ⟨tagReceipt,
    [asciiBytes r.witness, natToBytesBE r.cid, natToBytesBE r.bytes, natToBytesBE r.credits]⟩

/-- Read a receipt back out of an envelope. -/
def toReceipt (e : Envelope) : Option Receipt :=
  if e.tag ≠ tagReceipt then none
  else
    match e.fields with
    | [w, c, b, k] =>
        some ⟨asciiChars w, bytesBEToNat c, bytesBEToNat b, bytesBEToNat k⟩
    | _ => none

/-- The clipboard text of a result summary. -/
def copyReceipt (r : Receipt) : List Char := (ofReceipt r).encode

/-- Paste a result summary back. -/
def pasteReceipt (s : List Char) : Option Receipt := (Envelope.decode s).bind toReceipt

/-- **Results copy and paste exactly**, numbers included. -/
theorem pasteReceipt_copyReceipt {r : Receipt} (h : IsAscii r.witness) :
    pasteReceipt (copyReceipt r) = some r := by
  unfold pasteReceipt copyReceipt
  rw [Envelope.decode_encode]
  simp only [Option.bind_some, toReceipt, ofReceipt, ne_eq, not_true_eq_false, if_false,
    asciiChars_asciiBytes h, bytesBEToNat_natToBytesBE]

/-- The receipt of a post is always copyable: its witness is hex. -/
theorem isAscii_receiptOf_witness (p : Paste) (credits : Nat) :
    IsAscii (receiptOf p credits).witness :=
  isAscii_hexEncode (Kant.Bytes.digest p.content)

/-- **The results of a publish round-trip through the clipboard.** -/
theorem pasteReceipt_copyReceipt_of_paste (p : Paste) (credits : Nat) :
    pasteReceipt (copyReceipt (receiptOf p credits)) = some (receiptOf p credits) :=
  pasteReceipt_copyReceipt (isAscii_receiptOf_witness p credits)

/-! ## Sharing as a URL

The same envelope travels as the fragment of a URL: anything after the
first `'#'`.  A base URL never contains a `'#'`, so the fragment is
recovered exactly. -/

/-- The fragment marker. -/
def hash : Char := '#'

/-- A shareable URL for an envelope. -/
def shareUrl (base : List Char) (e : Envelope) : List Char :=
  base ++ hash :: e.encode

/-- The fragment of a URL: everything after the first `'#'`. -/
def fragment (u : List Char) : List Char :=
  match u with
  | [] => []
  | c :: cs => if c = hash then cs else fragment cs

/-- Recover an envelope from a shared URL. -/
def parseShareUrl (u : List Char) : Option Envelope := Envelope.decode (fragment u)

theorem fragment_append {base rest : List Char} (h : hash ∉ base) :
    fragment (base ++ hash :: rest) = rest := by
  induction base with
  | nil => simp [fragment]
  | cons c cs ih =>
      have hc : c ≠ hash := fun hc => h (by simp [hc])
      have hrest : hash ∉ cs := fun hx => h (by simp [hx])
      rw [List.cons_append, fragment, if_neg hc, ih hrest]

/-- **A shared link carries the whole result.** -/
theorem parseShareUrl_shareUrl {base : List Char} (h : hash ∉ base) (e : Envelope) :
    parseShareUrl (shareUrl base e) = some e := by
  unfold parseShareUrl shareUrl
  rw [fragment_append h, Envelope.decode_encode]

/-- **A post can be shared as a link and read back as the same post.** -/
theorem shareUrl_paste_roundTrip {base : List Char} (hb : hash ∉ base) {p : Paste}
    (h : Copyable p) :
    ((parseShareUrl (shareUrl base (ofPaste p))).bind toPaste) = some p := by
  rw [parseShareUrl_shareUrl hb]
  simpa using toPaste_ofPaste h

end Kant.Clipboard
