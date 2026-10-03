/-
# Copying a post as text

Copying a post used to put the machine-readable envelope on the
clipboard — `6b7a7061737465:2e2e2e:…` — which is useless in a chat
window.  This module specifies the other two ways of copying:

* **the text, and nothing else** (`copyPlain`): exactly the characters
  that were typed;
* **the text with an optional footer** (`copyPlainWithMeta`): the text,
  then a mail-style signature line `-- `, then a few `key: value` lines
  giving the title, the whole page link, the content address and the
  time.

Proved here:

* `copyPlain_eq_text` — the plain copy is the text itself, character for
  character;
* `copyPlain_ne_copyText` — and it really is not the encoded envelope,
  as soon as the text contains anything that is not a hex digit;
* `bodyOf_copyPlainWithMeta` — with the footer attached, the text still
  comes back unchanged;
* `metaOf_copyPlainWithMeta` — and the footer reads back as exactly the
  details it was made from;
* `copyPlainWithMeta_link_visible`, `metaFor_link` — the footer carries
  the whole page URL, not a bare address;
* `metaText_lines_ne_sig` — the footer can never be mistaken for a
  second signature line, so the split is unambiguous.
-/
import Mathlib
import RequestProject.Kant.Bytes
import RequestProject.Kant.Text
import RequestProject.Kant.Paste
import RequestProject.Kant.Clipboard
import RequestProject.Kant.SiteCard
import RequestProject.Kant.Join

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.PlainText

open Kant Kant.Bytes Kant.Text Kant.Clipboard Kant.SiteCard

/-! ## Lines -/

/-- Put lines back together. -/
def joinCh (d : Char) : List (List Char) → List Char
  | [] => []
  | [l] => l
  | l :: ls => l ++ d :: joinCh d ls

/-- **Cutting text into lines and joining it back is the identity.** -/
theorem joinCh_splitCh (d : Char) (s : List Char) :
    joinCh d (Kant.SiteCard.splitCh d s) = s := by
  induction s with
  | nil => rfl
  | cons c cs ih =>
      cases hs : Kant.SiteCard.splitCh d cs with
      | nil => exact absurd hs (Kant.SiteCard.splitCh_ne_nil d cs)
      | cons f fs =>
          rw [hs] at ih
          by_cases hc : c = d
          · rw [Kant.SiteCard.splitCh, if_pos hc, hs]
            simpa [joinCh, hc] using ih
          · rw [Kant.SiteCard.splitCh, if_neg hc, hs]
            cases fs with
            | nil => simpa [joinCh] using ih
            | cons g gs => simpa [joinCh] using ih

/-- The lines of a piece of text. -/
def lines (s : List Char) : List (List Char) := Kant.SiteCard.splitCh '\n' s

theorem lines_append (a b : List Char) : lines (a ++ '\n' :: b) = lines a ++ lines b :=
  Kant.Join.splitCh_append_general '\n' a b

theorem lines_of_no_newline {s : List Char} (h : '\n' ∉ s) : lines s = [s] :=
  Kant.SiteCard.splitCh_of_not_mem h

/-! ## The footer -/

/-- The signature line that separates the text from its details, as in
mail: two dashes and a space. -/
def sigMark : List Char := "-- ".toList

/-- The details a post can carry under its text. -/
structure Meta where
  /-- The post's title. -/
  title : List Char
  /-- The whole page URL of the post. -/
  link : List Char
  /-- The content address: 64 hex characters. -/
  address : List Char
  /-- When it was posted. -/
  posted : List Char
deriving DecidableEq, Repr

/-- A detail line survives the round trip when it is one line and does
not begin with a space. -/
structure Meta.Wf (m : Meta) : Prop where
  /-- The title is one line, no leading space. -/
  title : Kant.SiteCard.FieldOk m.title
  /-- The link is one line, no leading space. -/
  link : Kant.SiteCard.FieldOk m.link
  /-- The address is one line, no leading space. -/
  address : Kant.SiteCard.FieldOk m.address
  /-- The time is one line, no leading space. -/
  posted : Kant.SiteCard.FieldOk m.posted

/-- One `key: value` line of the footer. -/
def entry (key value : List Char) : List Char := key ++ ": ".toList ++ value ++ ['\n']

/-- The footer: the details, one per line. -/
def metaText (m : Meta) : List Char :=
  entry "title".toList m.title ++ entry "link".toList m.link ++
    entry "address".toList m.address ++ entry "posted".toList m.posted

/-- Read one `key: value` line. -/
def parseEntry (l : List Char) : Option (List Char × List Char) :=
  (Kant.SiteCard.breakAt ':' l).map
    (fun p => (Kant.SiteCard.trimEnd p.1, Kant.SiteCard.trimStart p.2))

/-- Read the footer. -/
def parseMeta (s : List Char) : Option Meta := do
  let es := (lines s).filterMap parseEntry
  let title ← Kant.SiteCard.lookupKey "title".toList es
  let link ← Kant.SiteCard.lookupKey "link".toList es
  let address ← Kant.SiteCard.lookupKey "address".toList es
  let posted ← Kant.SiteCard.lookupKey "posted".toList es
  pure ⟨title, link, address, posted⟩

theorem parseEntry_line {k v : List Char} (heq : ':' ∉ k) (hs : ' ' ∉ k)
    (hv : v.head? ≠ some ' ') : parseEntry (k ++ ": ".toList ++ v) = some (k, v) := by
  have hsplit : k ++ ": ".toList ++ v = k ++ ':' :: (' ' :: v) := by
    simp only [List.append_assoc]; rfl
  rw [parseEntry, hsplit, Kant.SiteCard.breakAt_append heq]
  simp only [Option.map_some]
  rw [Kant.SiteCard.trimStart_cons_space hv]
  have htrim : Kant.SiteCard.trimEnd k = k := by
    unfold Kant.SiteCard.trimEnd
    cases hk : k.reverse with
    | nil =>
        have hk0 : k = [] := by simpa using congrArg List.reverse hk
        simp [hk0]
    | cons x xs =>
        have hx : x ≠ ' ' := by
          rintro rfl
          exact hs (by rw [← List.mem_reverse, hk]; simp)
        rw [List.dropWhile_cons_of_neg (by simpa using hx), ← hk, List.reverse_reverse]
  rw [htrim]

theorem lines_entry {k v rest : List Char} (hk : '\n' ∉ k) (hv : '\n' ∉ v) :
    lines (entry k v ++ rest) = (k ++ ": ".toList ++ v) :: lines rest := by
  have hline : '\n' ∉ k ++ ": ".toList ++ v := by
    simp only [List.mem_append]
    push_neg
    exact ⟨⟨hk, by decide⟩, hv⟩
  have hassoc : entry k v ++ rest = (k ++ ": ".toList ++ v) ++ '\n' :: rest := by
    simp [entry]
  rw [hassoc, lines, Kant.SiteCard.splitCh_append hline]
  rfl

theorem lines_metaText {m : Meta} (h : m.Wf) :
    lines (metaText m) =
      ["title".toList ++ ": ".toList ++ m.title,
       "link".toList ++ ": ".toList ++ m.link,
       "address".toList ++ ": ".toList ++ m.address,
       "posted".toList ++ ": ".toList ++ m.posted, []] := by
  have hr : metaText m =
      entry "title".toList m.title ++ (entry "link".toList m.link ++
        (entry "address".toList m.address ++ (entry "posted".toList m.posted ++ []))) := by
    simp [metaText]
  rw [hr, lines_entry (by decide) h.title.oneLine, lines_entry (by decide) h.link.oneLine,
    lines_entry (by decide) h.address.oneLine, lines_entry (by decide) h.posted.oneLine]
  rfl

/-- **The footer reads back as the details it was made from.** -/
theorem parseMeta_metaText {m : Meta} (h : m.Wf) : parseMeta (metaText m) = some m := by
  have e1 := parseEntry_line (k := "title".toList) (v := m.title)
    (by decide) (by decide) h.title.noLeadingSpace
  have e2 := parseEntry_line (k := "link".toList) (v := m.link)
    (by decide) (by decide) h.link.noLeadingSpace
  have e3 := parseEntry_line (k := "address".toList) (v := m.address)
    (by decide) (by decide) h.address.noLeadingSpace
  have e4 := parseEntry_line (k := "posted".toList) (v := m.posted)
    (by decide) (by decide) h.posted.noLeadingSpace
  have hempty : parseEntry [] = none := rfl
  rw [parseMeta, lines_metaText h]
  simp only [List.filterMap_cons, e1, e2, e3, e4, hempty, List.filterMap_nil]
  simp +decide [Kant.SiteCard.lookupKey]

/-- **No line of the footer can be mistaken for the signature line.** -/
theorem metaText_lines_ne_sig {m : Meta} (h : m.Wf) :
    ∀ l ∈ lines (metaText m), l ≠ sigMark := by
  have hsig : sigMark.length = 3 := rfl
  have h1 : "title".length = 5 := rfl
  have h2 : "link".length = 4 := rfl
  have h3 : "address".length = 7 := rfl
  have h4 : "posted".length = 6 := rfl
  have h5 : ": ".length = 2 := rfl
  rw [lines_metaText h]
  intro l hl
  simp only [List.mem_cons, List.not_mem_nil, or_false] at hl
  rcases hl with rfl | rfl | rfl | rfl | rfl
  · intro hx
    have := congrArg List.length hx
    simp only [List.length_append, String.length_toList, hsig] at this
    omega
  · intro hx
    have := congrArg List.length hx
    simp only [List.length_append, String.length_toList, hsig] at this
    omega
  · intro hx
    have := congrArg List.length hx
    simp only [List.length_append, String.length_toList, hsig] at this
    omega
  · intro hx
    have := congrArg List.length hx
    simp only [List.length_append, String.length_toList, hsig] at this
    omega
  · intro hx
    have hlen := congrArg List.length hx
    rw [hsig] at hlen
    simp at hlen

/-! ## Copying -/

/-- The text of a post, as it was typed. -/
def plainText (p : Paste) : List Char := asciiChars p.content

/-- **Copying the text gives the text.** -/
def copyPlain (p : Paste) : List Char := plainText p

/-- The text with the footer under it. -/
def render (body : List Char) (m : Meta) : List Char :=
  body ++ '\n' :: (sigMark ++ '\n' :: metaText m)

/-- The details of a post in a given deployment: its title, its whole
page URL, its address and its time. -/
def metaFor (c : Config) (p : Paste) : Meta :=
  ⟨p.title, Kant.SiteCard.pasteUrl c p, p.witness, p.timestamp⟩

/-- **Copying the text with its details.** -/
def copyPlainWithMeta (c : Config) (p : Paste) : List Char :=
  render (plainText p) (metaFor c p)

/-- The text part of something copied this way: everything above the
signature line. -/
def bodyOf (s : List Char) : List Char :=
  joinCh '\n' ((lines s).takeWhile (fun l => l ≠ sigMark))

/-- The footer part, if there is one. -/
def metaTextOf (s : List Char) : List Char :=
  joinCh '\n' (((lines s).dropWhile (fun l => l ≠ sigMark)).drop 1)

/-- The details, if the text carries any. -/
def metaOf (s : List Char) : Option Meta := parseMeta (metaTextOf s)

@[simp] theorem copyPlain_eq_text (p : Paste) : copyPlain p = plainText p := rfl

/-- **What is copied is what was typed** — the characters of the post,
not an encoding of them. -/
theorem copyPlain_eq_content (p : Paste) : copyPlain p = asciiChars p.content := rfl

/-- **And it is not the machine-readable envelope.**  As soon as the
text contains one character that a code cannot contain — a space, a full
stop, a capital letter — the plain copy and the envelope differ. -/
theorem copyPlain_ne_copyText {p : Paste} {ch : Char} (hmem : ch ∈ copyPlain p)
    (hch : Kant.Join.isCodeChar ch = false) : copyPlain p ≠ copyText p := by
  intro heq
  rw [heq] at hmem
  have := Kant.Join.allCode_encode (ofPaste p) ch hmem
  rw [this] at hch
  exact absurd hch (by decide)

theorem lines_render (body : List Char) (m : Meta) :
    lines (render body m) = lines body ++ sigMark :: lines (metaText m) := by
  show lines (body ++ '\n' :: (sigMark ++ '\n' :: metaText m)) = _
  rw [lines_append, lines_append, lines_of_no_newline (show '\n' ∉ sigMark by decide)]
  rfl

theorem takeWhile_append_sep {α : Type} {p : α → Bool} {a : List α} {d : α} {b : List α}
    (ha : ∀ y ∈ a, p y = true) (hd : p d = false) : (a ++ d :: b).takeWhile p = a := by
  induction a with
  | nil => simp [hd]
  | cons c cs ih =>
      rw [List.cons_append, List.takeWhile_cons_of_pos (ha c (by simp)),
        ih (fun x hx => ha x (by simp [hx]))]

theorem takeWhile_lines_render (body : List Char) (m : Meta)
    (hb : ∀ l ∈ lines body, l ≠ sigMark) :
    ((lines (render body m)).takeWhile (fun l => l ≠ sigMark)) = lines body := by
  rw [lines_render]
  refine takeWhile_append_sep ?_ (by simp)
  intro l hl
  exact decide_eq_true (hb l hl)

/-- **The text survives the footer.**  Copy the post with its details,
paste it back, and the text above the signature line is exactly the text
that was typed — unless the text itself contains a line that is a
signature line. -/
theorem bodyOf_render {body : List Char} {m : Meta}
    (hb : ∀ l ∈ lines body, l ≠ sigMark) : bodyOf (render body m) = body := by
  rw [bodyOf, takeWhile_lines_render body m hb, lines, joinCh_splitCh]

theorem dropWhile_append_sep {α : Type} {p : α → Bool} {a : List α} {x : α} {b : List α}
    (ha : ∀ y ∈ a, p y = true) (hx : p x = false) : (a ++ x :: b).dropWhile p = x :: b := by
  induction a with
  | nil => simp [hx]
  | cons y ys ih =>
      rw [List.cons_append, List.dropWhile_cons_of_pos (ha y (by simp))]
      exact ih (fun z hz => ha z (by simp [hz]))

theorem dropWhile_lines_render (body : List Char) (m : Meta)
    (hb : ∀ l ∈ lines body, l ≠ sigMark) :
    (((lines (render body m)).dropWhile (fun l => l ≠ sigMark)).drop 1) =
      lines (metaText m) := by
  rw [lines_render, dropWhile_append_sep (fun l hl => by simpa using hb l hl)
    (by simp only [ne_eq, decide_not, decide_true, Bool.not_true])]
  rfl

/-- **The details survive too.** -/
theorem metaOf_render {body : List Char} {m : Meta} (h : m.Wf)
    (hb : ∀ l ∈ lines body, l ≠ sigMark) : metaOf (render body m) = some m := by
  rw [metaOf, metaTextOf, dropWhile_lines_render body m hb, lines, joinCh_splitCh,
    parseMeta_metaText h]

/-- **Copying a post as text with its details: the text comes back.** -/
theorem bodyOf_copyPlainWithMeta {c : Config} {p : Paste}
    (hb : ∀ l ∈ lines (plainText p), l ≠ sigMark) :
    bodyOf (copyPlainWithMeta c p) = plainText p :=
  bodyOf_render hb

/-- **…and so do the details.** -/
theorem metaOf_copyPlainWithMeta {c : Config} {p : Paste} (h : (metaFor c p).Wf)
    (hb : ∀ l ∈ lines (plainText p), l ≠ sigMark) :
    metaOf (copyPlainWithMeta c p) = some (metaFor c p) :=
  metaOf_render h hb

/-- The footer's link is the whole page URL of the post, not a bare
address. -/
@[simp] theorem metaFor_link (c : Config) (p : Paste) :
    (metaFor c p).link = Kant.SiteCard.pasteUrl c p := rfl

/-- **The whole link is printed in the footer.** -/
theorem copyPlainWithMeta_link_visible (c : Config) (p : Paste) :
    Kant.SiteCard.pasteUrl c p <:+: copyPlainWithMeta c p := by
  set m := metaFor c p with hm
  have h1 : m.link <:+: entry "link".toList m.link :=
    ⟨"link".toList ++ ": ".toList, ['\n'], by simp [entry]⟩
  have h2 : entry "link".toList m.link <:+: metaText m :=
    ⟨entry "title".toList m.title,
      entry "address".toList m.address ++ entry "posted".toList m.posted, by
        simp [metaText]⟩
  have h3 : metaText m <:+: copyPlainWithMeta c p :=
    ⟨plainText p ++ '\n' :: sigMark ++ ['\n'], [], by
      simp [copyPlainWithMeta, render, hm]⟩
  have := (h1.trans h2).trans h3
  simpa [hm] using this

theorem isAscii_append {a b : List Char} (ha : IsAscii a) (hb : IsAscii b) :
    IsAscii (a ++ b) := by
  intro c hc
  rcases List.mem_append.mp hc with h | h
  · exact ha c h
  · exact hb c h

theorem isAscii_entry {k v : List Char} (hk : IsAscii k) (hv : IsAscii v) :
    IsAscii (entry k v) := by
  unfold entry
  refine isAscii_append (isAscii_append (isAscii_append hk ?_) hv) ?_
  · intro c hc; fin_cases hc; all_goals decide
  · intro c hc; fin_cases hc; all_goals decide

/-- The footer is ASCII whenever its details are. -/
theorem isAscii_metaText {m : Meta} (ht : IsAscii m.title) (hl : IsAscii m.link)
    (ha : IsAscii m.address) (hp : IsAscii m.posted) : IsAscii (metaText m) := by
  unfold metaText
  refine isAscii_append (isAscii_append (isAscii_append ?_ ?_) ?_) ?_
  · exact isAscii_entry (by intro c hc; fin_cases hc; all_goals decide) ht
  · exact isAscii_entry (by intro c hc; fin_cases hc; all_goals decide) hl
  · exact isAscii_entry (by intro c hc; fin_cases hc; all_goals decide) ha
  · exact isAscii_entry (by intro c hc; fin_cases hc; all_goals decide) hp

end Kant.PlainText
