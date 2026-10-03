/-
# The site URL, the configuration file, and the share card

Everything this client hands to somebody else — a QR code, a link, a
message in chat — should carry the **whole address of the page**, not a
bare payload:

```
https://kant.cicada71.net/#ff810f291f187b808a0183f83c0466874573ef5c4c6d7d9ed430c6f7d710f605
```

The part before the `'#'` is deployment data, not program data, so it
lives in a configuration file that also names the caption and the little
picture printed on the code.  This module specifies

* the configuration file (`Config`, `renderConfig`, `parseConfig`),
* the URLs built from it (`addressUrl`, `pasteUrl`, `shareUrl`,
  `qrPayload`) — the payload of every code is the full URL,
* the **share card**: that URL, a line of text and a picture, rendered as
  one SVG document (`cardSvg`), and
* sharing the card **in chat** (`cardLine`, `chatMsg`, `chatText`).

Proved here:

* `parseConfig_renderConfig` — a configuration file written by this
  client reads back as the same configuration;
* `urlAddress_addressUrl`, `pasteUrl_address`, `pasteUrl_length` — the
  URL is the configured origin, a `'#'` and the 64-hex address of the
  content, and the address comes back out of it;
* `parseQrPayload_qrPayload` — what a code carries is a URL a plain
  scanner can open (`qrPayload_origin_prefix`) *and* the exact envelope
  the sender meant;
* `readCard_cardSvg` — the picture with the caption and the logo still
  carries the card it was made from;
* `cardSvg_caption_visible`, `cardSvg_picture_used`, `cardSvg_url_visible`
  and `card_text_no_markup` — the text, the URL and the picture really
  appear in the document, and none of them can break out of its element;
* `logo_area_bound` — the picture in the middle covers at most a
  twenty-fifth of the code's modules, well inside the error-correction
  budget;
* `readChatCard_chatMsg`, `readChatText_chatText` — a card shared in a
  chat room reads back as the same card, and a doctored chat line is
  refused (`chatMsg_tamper`).
-/
import Mathlib
import RequestProject.Kant.Bytes
import RequestProject.Kant.Text
import RequestProject.Kant.Paste
import RequestProject.Kant.Erdfa
import RequestProject.Kant.Clipboard
import RequestProject.Kant.Sneakernet
import RequestProject.Kant.Relay

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.SiteCard

open Kant Kant.Bytes Kant.Text Kant.Clipboard

/-! ## Splitting text at a delimiter

The configuration file is a list of lines, and a chat share is a couple
of lines of text followed by the machine-readable card.  Both need the
same one-character split, so it is proved once here. -/

/-- Split at every occurrence of `d`.  Always returns at least one part. -/
def splitCh (d : Char) : List Char → List (List Char)
  | [] => [[]]
  | c :: cs =>
      if c = d then [] :: splitCh d cs
      else
        match splitCh d cs with
        | [] => [[c]]
        | f :: fs => (c :: f) :: fs

theorem splitCh_ne_nil (d : Char) (s : List Char) : splitCh d s ≠ [] := by
  induction s with
  | nil => simp [splitCh]
  | cons c cs ih =>
      unfold splitCh
      split
      · simp
      · split <;> simp

/-- Text without the delimiter is a single part. -/
theorem splitCh_of_not_mem {d : Char} {f : List Char} (h : d ∉ f) : splitCh d f = [f] := by
  induction f with
  | nil => rfl
  | cons c cs ih =>
      have hc : c ≠ d := fun hc => h (by simp [hc])
      have hrest : d ∉ cs := fun hx => h (by simp [hx])
      rw [splitCh, if_neg hc, ih hrest]

/-- Splitting peels off one delimiter-free part at a time. -/
theorem splitCh_append {d : Char} {f rest : List Char} (h : d ∉ f) :
    splitCh d (f ++ d :: rest) = f :: splitCh d rest := by
  induction f with
  | nil => simp [splitCh]
  | cons c cs ih =>
      have hc : c ≠ d := fun hc => h (by simp [hc])
      have hrest : d ∉ cs := fun hx => h (by simp [hx])
      rw [List.cons_append, splitCh, if_neg hc, ih hrest]

/-- Break at the first occurrence of `d`: the text before it and the text
after it. -/
def breakAt (d : Char) : List Char → Option (List Char × List Char)
  | [] => none
  | c :: cs => if c = d then some ([], cs) else (breakAt d cs).map (fun p => (c :: p.1, p.2))

theorem breakAt_append {d : Char} {a b : List Char} (h : d ∉ a) :
    breakAt d (a ++ d :: b) = some (a, b) := by
  induction a with
  | nil => simp [breakAt]
  | cons c cs ih =>
      have hc : c ≠ d := fun hc => h (by simp [hc])
      have hrest : d ∉ cs := fun hx => h (by simp [hx])
      simp [breakAt, hc, ih hrest]

/-! ## The configuration file

```
# where this deployment lives
origin = https://kant.cicada71.net/
caption = kant-zk-pastebin
picture = ./kant-logo.svg
alt = the Kant pastebin logo
```

Lines are `key = value`; anything without an `'='` — a comment, a blank
line — is ignored. -/

/-- The deployment configuration: the site the codes point at, and how
the share card is dressed. -/
structure Config where
  /-- The site URL that every code and link starts with, `'#'` excluded. -/
  origin : List Char
  /-- The line of text printed on the card. -/
  caption : List Char
  /-- The little picture placed in the middle of the code. -/
  picture : List Char
  /-- The picture's text description. -/
  alt : List Char
deriving DecidableEq, Repr

/-- A field of the configuration file survives a write/read round trip
when it occupies one line and does not begin with a space. -/
structure FieldOk (s : List Char) : Prop where
  /-- The value stays on its own line. -/
  oneLine : '\n' ∉ s
  /-- A leading space would be eaten when the value is read back. -/
  noLeadingSpace : s.head? ≠ some ' '

/-- A usable configuration: every field round-trips through the file, the
origin has no fragment marker of its own, and it is plain ASCII. -/
structure Config.Wf (c : Config) : Prop where
  /-- The origin is one line, without a leading space. -/
  origin : FieldOk c.origin
  /-- The caption is one line, without a leading space. -/
  caption : FieldOk c.caption
  /-- The picture reference is one line, without a leading space. -/
  picture : FieldOk c.picture
  /-- The description is one line, without a leading space. -/
  alt : FieldOk c.alt
  /-- The origin carries no `'#'`: the fragment is ours to write. -/
  noHash : Kant.Clipboard.hash ∉ c.origin
  /-- The origin is ASCII, so it travels through any channel. -/
  ascii : IsAscii c.origin

/-- One `key = value` line, newline included. -/
def entry (key value : List Char) : List Char := key ++ " = ".toList ++ value ++ ['\n']

/-- Write the configuration file. -/
def renderConfig (c : Config) : List Char :=
  entry "origin".toList c.origin ++ entry "caption".toList c.caption ++
    entry "picture".toList c.picture ++ entry "alt".toList c.alt

/-- Drop the spaces at the end of a key. -/
def trimEnd (s : List Char) : List Char := (s.reverse.dropWhile (· = ' ')).reverse

/-- Drop the spaces at the start of a value. -/
def trimStart (s : List Char) : List Char := s.dropWhile (· = ' ')

/-- Read one line of the configuration file. -/
def parseEntry (l : List Char) : Option (List Char × List Char) :=
  (breakAt '=' l).map (fun p => (trimEnd p.1, trimStart p.2))

/-- Look a key up among the lines that were read. -/
def lookupKey (k : List Char) : List (List Char × List Char) → Option (List Char)
  | [] => none
  | (k', v) :: rest => if k' = k then some v else lookupKey k rest

/-- Read the configuration file. -/
def parseConfig (s : List Char) : Option Config := do
  let es := (splitCh '\n' s).filterMap parseEntry
  let origin ← lookupKey "origin".toList es
  let caption ← lookupKey "caption".toList es
  let picture ← lookupKey "picture".toList es
  let alt ← lookupKey "alt".toList es
  pure ⟨origin, caption, picture, alt⟩

theorem trimStart_cons_space {v : List Char} (h : v.head? ≠ some ' ') :
    trimStart (' ' :: v) = v := by
  unfold trimStart
  cases v with
  | nil => simp
  | cons c cs =>
      have hc : c ≠ ' ' := by simpa using h
      simp [List.dropWhile, hc]

theorem trimEnd_append_space {k : List Char} (h : ' ' ∉ k) : trimEnd (k ++ [' ']) = k := by
  unfold trimEnd
  cases hk : k.reverse with
  | nil => simp_all
  | cons c cs =>
      have hc : c ≠ ' ' := by
        intro hc; subst hc
        exact h (by rw [← List.mem_reverse, hk]; simp)
      simp [List.reverse_append, hk, List.dropWhile, hc]
      simpa using congrArg List.reverse hk.symm

theorem parseEntry_line {k v : List Char} (heq : '=' ∉ k) (hs : ' ' ∉ k)
    (hv : v.head? ≠ some ' ') :
    parseEntry (k ++ " = ".toList ++ v) = some (k, v) := by
  have hsplit : k ++ " = ".toList ++ v = (k ++ [' ']) ++ '=' :: (' ' :: v) := by
    simp only [List.append_assoc]; rfl
  have hne : '=' ∉ k ++ [' '] := by
    simp only [List.mem_append, List.mem_singleton]
    rintro (h | h)
    · exact heq h
    · exact absurd h (by decide)
  rw [parseEntry, hsplit, breakAt_append hne]
  simp [trimEnd_append_space hs, trimStart_cons_space hv]

theorem splitCh_entry {k v rest : List Char} (hk : '\n' ∉ k) (hv : '\n' ∉ v) :
    splitCh '\n' (entry k v ++ rest) = (k ++ " = ".toList ++ v) :: splitCh '\n' rest := by
  have hline : '\n' ∉ k ++ " = ".toList ++ v := by
    simp only [List.mem_append]
    push_neg
    exact ⟨⟨hk, by decide⟩, hv⟩
  have hassoc : entry k v ++ rest = (k ++ " = ".toList ++ v) ++ '\n' :: rest := by
    simp [entry]
  rw [hassoc, splitCh_append hline]

/-- **The configuration file round-trips.**  What this client writes to
`kant.config` is read back as exactly the configuration it wrote. -/
theorem parseConfig_renderConfig {c : Config} (h : c.Wf) :
    parseConfig (renderConfig c) = some c := by
  have hr : renderConfig c =
      entry "origin".toList c.origin ++ (entry "caption".toList c.caption ++
        (entry "picture".toList c.picture ++ (entry "alt".toList c.alt ++ []))) := by
    simp [renderConfig]
  have hsplit : splitCh '\n' (renderConfig c) =
      ["origin".toList ++ " = ".toList ++ c.origin,
       "caption".toList ++ " = ".toList ++ c.caption,
       "picture".toList ++ " = ".toList ++ c.picture,
       "alt".toList ++ " = ".toList ++ c.alt, []] := by
    rw [hr, splitCh_entry (by decide) h.origin.oneLine,
      splitCh_entry (by decide) h.caption.oneLine,
      splitCh_entry (by decide) h.picture.oneLine,
      splitCh_entry (by decide) h.alt.oneLine]
    simp [splitCh]
  have e1 := parseEntry_line (k := "origin".toList) (v := c.origin)
    (by decide) (by decide) h.origin.noLeadingSpace
  have e2 := parseEntry_line (k := "caption".toList) (v := c.caption)
    (by decide) (by decide) h.caption.noLeadingSpace
  have e3 := parseEntry_line (k := "picture".toList) (v := c.picture)
    (by decide) (by decide) h.picture.noLeadingSpace
  have e4 := parseEntry_line (k := "alt".toList) (v := c.alt)
    (by decide) (by decide) h.alt.noLeadingSpace
  have hempty : parseEntry [] = none := rfl
  rw [parseConfig, hsplit]
  simp only [List.filterMap_cons, e1, e2, e3, e4, hempty, List.filterMap_nil]
  simp +decide [lookupKey]

/-- A configuration line that carries no `'='` — a comment, a blank line
— is ignored. -/
theorem parseConfig_ignores_comment {l s : List Char} (h : '=' ∉ l) (hn : '\n' ∉ l) :
    parseConfig (l ++ '\n' :: s) = parseConfig s := by
  have hbreak : breakAt '=' l = none := by
    induction l with
    | nil => rfl
    | cons c cs ih =>
        have hc : c ≠ '=' := fun hc => h (by simp [hc])
        have hrest : '=' ∉ cs := fun hx => h (by simp [hx])
        have hn' : '\n' ∉ cs := fun hx => hn (by simp [hx])
        simp [breakAt, hc, ih hrest hn']
  simp [parseConfig, splitCh_append hn, parseEntry, hbreak]

/-! ## URLs built from the configuration -/

/-- The site address of a piece of content: the configured origin, the
fragment marker, and the content's address.

`addressUrl cfg w` is exactly the shape of a published page,
`https://kant.cicada71.net/#ff81…f605`. -/
def addressUrl (c : Config) (addr : List Char) : List Char :=
  c.origin ++ Kant.Clipboard.hash :: addr

/-- The address a URL points at. -/
def urlAddress (u : List Char) : List Char := Kant.Clipboard.fragment u

/-- The site address of a post. -/
def pasteUrl (c : Config) (p : Paste) : List Char := addressUrl c p.witness

/-- A whole envelope — a post, a receipt, an invitation, a mailbag —
carried in the fragment of the configured site URL. -/
def shareUrl (c : Config) (e : Envelope) : List Char := Kant.Clipboard.shareUrl c.origin e

/-- **What a code carries is the entire URL.**  Not the bare payload: a
scanner that knows nothing about this program still gets a link it can
open, and the client that does know reads the payload out of the
fragment. -/
def qrPayload (c : Config) (e : Envelope) : List Char := shareUrl c e

/-- Read the payload back out of a scanned URL. -/
def parseQrPayload (u : List Char) : Option Envelope := Kant.Clipboard.parseShareUrl u

/-- **The address comes back out of the URL.** -/
theorem urlAddress_addressUrl {c : Config} (h : c.Wf) (addr : List Char) :
    urlAddress (addressUrl c addr) = addr :=
  Kant.Clipboard.fragment_append h.noHash

theorem addressUrl_length (c : Config) (addr : List Char) :
    (addressUrl c addr).length = c.origin.length + addr.length + 1 := by
  simp [addressUrl]; omega

/-- A published page's URL is the origin, a `'#'` and 64 hex characters. -/
theorem pasteUrl_length (c : Config) (p : Paste) :
    (pasteUrl c p).length = c.origin.length + 65 := by
  simp [pasteUrl, addressUrl, Paste.witness_length]

/-- **The URL names the content it came from.** -/
theorem pasteUrl_address {c : Config} (h : c.Wf) (p : Paste) :
    urlAddress (pasteUrl c p) = p.witness :=
  urlAddress_addressUrl h _

/-- Two different addresses are two different URLs. -/
theorem addressUrl_injective {c : Config} (h : c.Wf) {a b : List Char}
    (heq : addressUrl c a = addressUrl c b) : a = b := by
  have hx := congrArg urlAddress heq
  rwa [urlAddress_addressUrl h, urlAddress_addressUrl h] at hx

/-- **Scanning the code recovers exactly what was shared.** -/
theorem parseQrPayload_qrPayload {c : Config} (h : c.Wf) (e : Envelope) :
    parseQrPayload (qrPayload c e) = some e :=
  Kant.Clipboard.parseShareUrl_shareUrl h.noHash e

/-- The payload of a code starts with the configured site: a scanner
that knows nothing about this program still offers an openable link. -/
theorem qrPayload_origin_prefix (c : Config) (e : Envelope) :
    c.origin <+: qrPayload c e := ⟨_, rfl⟩

/-- A page URL is ASCII, so it travels through any channel. -/
theorem isAscii_pasteUrl {c : Config} (h : c.Wf) (p : Paste) : IsAscii (pasteUrl c p) := by
  intro ch hch
  simp only [pasteUrl, addressUrl, List.mem_append, List.mem_cons] at hch
  rcases hch with hch | rfl | hch
  · exact h.ascii ch hch
  · decide
  · exact isAscii_hexEncode _ ch hch

/-- **A page URL fits in one QR code**, with room to spare for any
plausible origin. -/
theorem pasteUrl_fits_qr {c : Config} (h : c.origin.length ≤ 2888) (p : Paste) :
    (pasteUrl c p).length ≤ Kant.Sneakernet.Channel.qr.capacity := by
  have hcap : Kant.Sneakernet.Channel.qr.capacity = 2953 := rfl
  have hlen := pasteUrl_length c p
  omega

/-! ## The share card: a code, a line of text, a picture -/

/-- A share card: the URL the code carries, the text printed with it, the
picture placed in the middle of the code, and that picture's description. -/
structure Card where
  /-- The full site URL the code encodes. -/
  url : List Char
  /-- The line of text printed under the code. -/
  caption : List Char
  /-- The picture drawn in the middle of the code. -/
  picture : List Char
  /-- The picture's text description. -/
  alt : List Char
deriving DecidableEq, Repr

/-- Every text field of a card is ASCII, so the card copies, pastes and
travels as one line. -/
structure Card.Wf (k : Card) : Prop where
  /-- The URL is ASCII. -/
  url : IsAscii k.url
  /-- The caption is ASCII. -/
  caption : IsAscii k.caption
  /-- The picture reference is ASCII. -/
  picture : IsAscii k.picture
  /-- The description is ASCII. -/
  alt : IsAscii k.alt

/-- The card for a post, dressed by the configuration: the whole site URL
of the post, the configured caption and the configured picture. -/
def cardOf (c : Config) (p : Paste) : Card :=
  ⟨pasteUrl c p, c.caption, c.picture, c.alt⟩

@[simp] theorem cardOf_url (c : Config) (p : Paste) : (cardOf c p).url = pasteUrl c p := rfl

/-- Tag of a card on the wire. -/
def tagCard : Blob := asciiBytes "kzcard".toList

/-- A card as a copyable envelope. -/
def ofCard (k : Card) : Envelope :=
  ⟨tagCard, [asciiBytes k.url, asciiBytes k.caption, asciiBytes k.picture, asciiBytes k.alt]⟩

/-- Read a card back out of an envelope. -/
def toCard (e : Envelope) : Option Card :=
  if e.tag ≠ tagCard then none
  else
    match e.fields with
    | [u, c, p, a] => some ⟨asciiChars u, asciiChars c, asciiChars p, asciiChars a⟩
    | _ => none

/-- A card as one line of text. -/
def cardLine (k : Card) : List Char := (ofCard k).encode

/-- Read a card out of a line of text. -/
def readCardLine (s : List Char) : Option Card := (Envelope.decode s).bind toCard

theorem toCard_ofCard {k : Card} (h : k.Wf) : toCard (ofCard k) = some k := by
  cases k with
  | mk u c p a =>
      simp only [toCard, ofCard, ne_eq, not_true_eq_false, if_false,
        asciiChars_asciiBytes h.url, asciiChars_asciiBytes h.caption,
        asciiChars_asciiBytes h.picture, asciiChars_asciiBytes h.alt]

/-- **A card copies out and pastes back.** -/
theorem readCardLine_cardLine {k : Card} (h : k.Wf) : readCardLine (cardLine k) = some k := by
  unfold readCardLine cardLine
  rw [Envelope.decode_encode]
  simpa using toCard_ofCard h

/-- A card travels as plain ASCII. -/
theorem isAscii_cardLine (k : Card) : IsAscii (cardLine k) := Envelope.isAscii_encode _

/-! ### The card line never contains a newline

which is what lets the card ride in a comment at the top of an SVG
document, and on the last line of a chat message. -/

theorem not_mem_hexEncode {c : Char} (h : ∀ n, n < 16 → hexDigit n ≠ c) (bs : Blob) :
    c ∉ hexEncode bs := by
  intro hmem
  simp only [hexEncode, List.mem_flatMap] at hmem
  obtain ⟨b, _, hcb⟩ := hmem
  have hb : b.toNat < 256 := b.toNat_lt_size
  have h1 : b.toNat / 16 < 16 := by omega
  have h2 : b.toNat % 16 < 16 := Nat.mod_lt _ (by norm_num)
  simp only [hexByte, List.mem_cons, List.not_mem_nil, or_false] at hcb
  rcases hcb with hcb | hcb
  · exact h _ h1 hcb.symm
  · exact h _ h2 hcb.symm

theorem not_mem_joinFields {c : Char} (hs : c ≠ sep) {fs : List (List Char)}
    (h : ∀ f ∈ fs, c ∉ f) : c ∉ joinFields fs := by
  induction fs with
  | nil => simp [joinFields]
  | cons f fs ih =>
      cases fs with
      | nil => exact h f (by simp)
      | cons g gs =>
          rw [show joinFields (f :: g :: gs) = f ++ sep :: joinFields (g :: gs) from rfl]
          simp only [List.mem_append, List.mem_cons, not_or]
          exact ⟨h f (by simp), hs, ih (fun x hx => h x (by simp [hx]))⟩

theorem newline_not_mem_encode (e : Envelope) : '\n' ∉ e.encode := by
  refine not_mem_joinFields (by decide) ?_
  intro f hf
  simp only [List.mem_map] at hf
  obtain ⟨b, _, rfl⟩ := hf
  exact not_mem_hexEncode (by intro n hn; interval_cases n <;> decide) b

theorem newline_not_mem_cardLine (k : Card) : '\n' ∉ cardLine k := newline_not_mem_encode _

theorem takeWhile_append_sep {p : Char → Bool} {a b : List Char} {d : Char}
    (ha : ∀ c ∈ a, p c = true) (hd : p d = false) : (a ++ d :: b).takeWhile p = a := by
  induction a with
  | nil => simp [hd]
  | cons c cs ih =>
      rw [List.cons_append, List.takeWhile_cons_of_pos (ha c (by simp)),
        ih (fun x hx => ha x (by simp [hx]))]

/-! ### Rendering the card as a picture -/

/-- Decimal digits of a number, as characters. -/
def num (n : Nat) : List Char := (toString n).toList

/-- One dark module. -/
def moduleRect (x y scale border : Nat) : List Char :=
  "<rect x=\"".toList ++ num ((x + border) * scale) ++ "\" y=\"".toList ++
    num ((y + border) * scale) ++ "\" width=\"".toList ++ num scale ++
    "\" height=\"".toList ++ num scale ++ "\"/>".toList

/-- The dark modules of one row. -/
def rowRects (y scale border : Nat) : Nat → List Bool → List Char
  | _, [] => []
  | x, b :: bs =>
      (if b then moduleRect x y scale border else []) ++ rowRects y scale border (x + 1) bs

/-- The dark modules of the whole code. -/
def gridRects (scale border : Nat) : Nat → List (List Bool) → List Char
  | _, [] => []
  | y, row :: rows => rowRects y scale border 0 row ++ gridRects scale border (y + 1) rows

/-- The side, in modules, of the picture placed in the middle of a code
`n` modules across: a fifth of the code. -/
def logoSide (n : Nat) : Nat := n / 5

/-- **The picture never eats more than a twenty-fifth of the code.**  A
QR code at error-correction level H tolerates about thirty per cent of
its modules being unreadable, so a logo this size always leaves the code
scannable. -/
theorem logo_area_bound (n : Nat) : 25 * (logoSide n * logoSide n) ≤ n * n := by
  have h : 5 * logoSide n ≤ n := by
    simpa [logoSide, Nat.mul_comm] using Nat.div_mul_le_self n 5
  calc 25 * (logoSide n * logoSide n) = (5 * logoSide n) * (5 * logoSide n) := by ring
    _ ≤ n * n := Nat.mul_le_mul h h

/-- The marker that opens the machine-readable comment at the top of the
card. -/
def cardMarker : List Char := "<!--kzcard:".toList

/-- The drawing part of the card: the code as a clickable link, the
picture in the middle, and the caption and the URL as text.  Every
interpolated string is eRDFa-escaped, so no caption can break out of its
element. -/
def cardParts (k : Card) (modules : List (List Bool)) (scale border : Nat) : List (List Char) :=
  let n := modules.length
  let side := (n + 2 * border) * scale
  let height := side + 3 * scale
  let logo := logoSide n * scale
  let logoAt := (side - logo) / 2
  ["<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"".toList, num side,
   "\" height=\"".toList, num height, "\" viewBox=\"0 0 ".toList, num side, " ".toList, num height,
   "\" role=\"img\" aria-label=\"".toList, Kant.Erdfa.escape k.alt, "\">\n".toList,
   "<title>".toList, Kant.Erdfa.escape k.caption, "</title>\n".toList,
   "<rect width=\"100%\" height=\"100%\" fill=\"#fff\"/>\n".toList,
   "<a href=\"".toList, Kant.Erdfa.escape k.url, "\"><g fill=\"#000\">".toList,
   gridRects scale border 0 modules, "</g></a>\n".toList,
   "<image href=\"".toList, Kant.Erdfa.escape k.picture, "\" x=\"".toList, num logoAt,
   "\" y=\"".toList, num logoAt, "\" width=\"".toList, num logo, "\" height=\"".toList, num logo,
   "\"/>\n".toList,
   "<text x=\"".toList, num scale, "\" y=\"".toList, num (side + scale),
   "\" font-family=\"monospace\" font-size=\"".toList, num (2 * scale), "\" fill=\"#000\">".toList,
   Kant.Erdfa.escape k.caption, "</text>\n".toList,
   "<text x=\"".toList, num scale, "\" y=\"".toList, num (side + 3 * scale),
   "\" font-family=\"monospace\" font-size=\"".toList, num scale, "\" fill=\"#333\">".toList,
   Kant.Erdfa.escape k.url, "</text>\n".toList,
   "</svg>\n".toList]

/-- The card as one SVG document: a comment carrying the card itself,
then the drawing. -/
def cardSvg (k : Card) (modules : List (List Bool)) (scale border : Nat) : List Char :=
  cardMarker ++ cardLine k ++ '\n' :: "-->\n".toList ++
    (cardParts k modules scale border).flatten

/-- Read the card out of a card picture. -/
def readCard (doc : List Char) : Option Card :=
  if cardMarker.isPrefixOf doc then
    readCardLine ((doc.drop cardMarker.length).takeWhile (· ≠ '\n'))
  else none

/-- **The picture still carries the card.**  A share card exported as an
SVG — caption, logo and all — reads back as exactly the card it was made
from. -/
theorem readCard_cardSvg {k : Card} (h : k.Wf) (modules : List (List Bool)) (scale border : Nat) :
    readCard (cardSvg k modules scale border) = some k := by
  have hdoc : cardSvg k modules scale border =
      cardMarker ++ (cardLine k ++ '\n' ::
        ("-->\n".toList ++ (cardParts k modules scale border).flatten)) := by
    simp [cardSvg]
  have hpre : cardMarker.isPrefixOf (cardSvg k modules scale border) = true := by
    rw [hdoc, List.isPrefixOf_iff_prefix]
    exact ⟨_, rfl⟩
  have hdrop : (cardSvg k modules scale border).drop cardMarker.length =
      cardLine k ++ '\n' :: ("-->\n".toList ++ (cardParts k modules scale border).flatten) := by
    rw [hdoc, List.drop_left]
  have htake :
      ((cardSvg k modules scale border).drop cardMarker.length).takeWhile (· ≠ '\n') =
        cardLine k := by
    rw [hdrop]
    refine takeWhile_append_sep ?_ (by decide)
    intro c hc
    have := newline_not_mem_cardLine k
    simp only [decide_eq_true_eq, ne_eq]
    rintro rfl
    exact this hc
  rw [readCard, if_pos hpre, htake, readCardLine_cardLine h]

theorem flatten_infix_cardSvg (k : Card) (modules : List (List Bool)) (scale border : Nat) :
    (cardParts k modules scale border).flatten <:+: cardSvg k modules scale border := by
  have hdoc : cardSvg k modules scale border =
      (cardMarker ++ cardLine k ++ ['\n'] ++ "-->\n".toList) ++
        (cardParts k modules scale border).flatten := by
    simp [cardSvg]
  rw [hdoc]
  exact (List.suffix_append _ _).isInfix

theorem part_infix_cardSvg {k : Card} {modules : List (List Bool)} {scale border : Nat}
    {part : List Char} (h : part ∈ cardParts k modules scale border) :
    part <:+: cardSvg k modules scale border :=
  (List.infix_of_mem_flatten h).trans (flatten_infix_cardSvg k modules scale border)

/-- **The caption really is printed on the card.** -/
theorem cardSvg_caption_visible (k : Card) (modules : List (List Bool)) (scale border : Nat) :
    Kant.Erdfa.escape k.caption <:+: cardSvg k modules scale border :=
  part_infix_cardSvg (by simp [cardParts])

/-- **The picture really is placed on the card.** -/
theorem cardSvg_picture_used (k : Card) (modules : List (List Bool)) (scale border : Nat) :
    Kant.Erdfa.escape k.picture <:+: cardSvg k modules scale border :=
  part_infix_cardSvg (by simp [cardParts])

/-- **The whole URL is printed on the card**, so a reader who cannot scan
can still type it in. -/
theorem cardSvg_url_visible (k : Card) (modules : List (List Bool)) (scale border : Nat) :
    Kant.Erdfa.escape k.url <:+: cardSvg k modules scale border :=
  part_infix_cardSvg (by simp [cardParts])

/-- **No caption, URL or picture reference can break out of its element.**
Whatever the user types, the document stays well formed. -/
theorem card_text_no_markup (k : Card) :
    ('<' ∉ Kant.Erdfa.escape k.caption ∧ '>' ∉ Kant.Erdfa.escape k.caption ∧
        '"' ∉ Kant.Erdfa.escape k.caption) ∧
    ('<' ∉ Kant.Erdfa.escape k.url ∧ '>' ∉ Kant.Erdfa.escape k.url ∧
        '"' ∉ Kant.Erdfa.escape k.url) ∧
    ('<' ∉ Kant.Erdfa.escape k.picture ∧ '>' ∉ Kant.Erdfa.escape k.picture ∧
        '"' ∉ Kant.Erdfa.escape k.picture) ∧
    ('<' ∉ Kant.Erdfa.escape k.alt ∧ '>' ∉ Kant.Erdfa.escape k.alt ∧
        '"' ∉ Kant.Erdfa.escape k.alt) :=
  ⟨Kant.Erdfa.escape_no_markup _, Kant.Erdfa.escape_no_markup _,
    Kant.Erdfa.escape_no_markup _, Kant.Erdfa.escape_no_markup _⟩

/-- The caption a reader sees is the caption that was written. -/
theorem cardSvg_caption_recoverable (k : Card) :
    Kant.Erdfa.unescape (Kant.Erdfa.escape k.caption) = k.caption :=
  Kant.Erdfa.escape_unescape_id _

/-- **End to end: the card of a post carries that post's page URL.**
Export the picture, scan or read it back, and the URL you get is the full
site address of the post. -/
theorem cardOf_roundTrip {c : Config} {p : Paste} (h : (cardOf c p).Wf)
    (modules : List (List Bool)) (scale border : Nat) :
    (readCard (cardSvg (cardOf c p) modules scale border)).map Card.url = some (pasteUrl c p) := by
  rw [readCard_cardSvg h]
  rfl

/-! ## Sharing the card in chat -/

/-- A card posted into a chat room: an ordinary self-certifying chat
message whose body is the card. -/
def chatMsg (room sender : List Char) (seq : Nat) (k : Card) : Kant.Relay.Msg :=
  ⟨room, sender, seq, asciiBytes (cardLine k)⟩

/-- Read a card out of a chat line. -/
def readChatCard (line : List Char) : Option Card :=
  (Kant.Relay.parseMsg line).bind (fun m => readCardLine (asciiChars m.body))

/-- **A card shared in chat arrives as the same card.** -/
theorem readChatCard_chatMsg {k : Card} (hk : k.Wf) {room sender : List Char}
    (hr : IsAscii room) (hs : IsAscii sender) (seq : Nat) :
    readChatCard (Kant.Relay.printMsg (chatMsg room sender seq k)) = some k := by
  unfold readChatCard
  rw [Kant.Relay.parseMsg_printMsg ⟨hr, hs⟩]
  simp only [Option.bind_some, chatMsg]
  rw [asciiChars_asciiBytes (isAscii_cardLine k), readCardLine_cardLine hk]

/-- **A relay cannot doctor a shared card.**  If the body that arrives is
not the body the witness commits to, the line is refused outright rather
than displayed as somebody else's card. -/
theorem chatMsg_tamper {r s q b w : Blob}
    (h : (Kant.Relay.Msg.mk (asciiChars r) (asciiChars s) (bytesBEToNat q) b).witness ≠
      asciiChars w) :
    readChatCard (Envelope.encode ⟨Kant.Relay.tagChat, [r, s, q, b, w]⟩) = none := by
  unfold readChatCard Kant.Relay.parseMsg
  rw [Envelope.decode_encode]
  simp [Kant.Relay.parseMsg_eq_none_of_mismatch h]

/-- A card for a chat that carries nothing but text: what a human reads,
then the link, then the card itself on its own last line. -/
def chatText (k : Card) : List Char :=
  k.caption ++ '\n' :: (k.url ++ '\n' :: cardLine k)

/-- Read the card out of such a message: it is the last line. -/
def readChatText (s : List Char) : Option Card :=
  ((splitCh '\n' s).getLast?).bind readCardLine

/-- **A card pasted into any chat window comes back whole**, however the
human text above it is written. -/
theorem readChatText_chatText {k : Card} (hk : k.Wf) (hc : '\n' ∉ k.caption)
    (hu : '\n' ∉ k.url) : readChatText (chatText k) = some k := by
  have hsplit : splitCh '\n' (chatText k) = [k.caption, k.url, cardLine k] := by
    unfold chatText
    rw [splitCh_append hc, splitCh_append hu,
      splitCh_of_not_mem (newline_not_mem_cardLine k)]
  rw [readChatText, hsplit]
  simpa using readCardLine_cardLine hk

/-- The human sees the caption and the link before the machine-readable
line. -/
theorem chatText_shows_url (k : Card) : k.url <:+: chatText k := by
  refine ⟨k.caption ++ ['\n'], '\n' :: cardLine k, ?_⟩
  simp [chatText]

end Kant.SiteCard
