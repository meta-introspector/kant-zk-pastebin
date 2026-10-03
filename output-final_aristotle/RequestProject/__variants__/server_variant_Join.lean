/-
# Joining: one link, pasted however it arrives

Joining a room used to fail unless the text pasted was *exactly* the
invitation.  A link that came back from a chat window rarely is: it
arrives wrapped in a sentence, with a newline after it, a full stop
glued to its end, or inside angle brackets.

This module specifies a paste that tolerates all of that.  The text is
cut into words at any whitespace; in each word everything up to and
including the last `'#'` is dropped (so a link becomes its fragment),
and anything at either end that cannot occur inside a code — a bracket,
a full stop, a comma — is trimmed away.  The first word that decodes to
an invitation wins.

Definitions: `isCodeChar`, `isBlank`, `words`, `afterLastHash`,
`codePart`, `wordInvite`, `findInvite`.

Proved here:

* `findInvite_inviteUrl`, `findInvite_copyInvite` — the plain link and
  the bare code still work;
* `wordInvite_junk` — junk glued to either end of the link (brackets,
  punctuation, a `mailto:`-style prefix) does not stop it being read;
* `findInvite_in_message` — a link pasted inside a sentence, with
  whatever text before and after it, still joins the same room;
* `findInvite_trailing_newline` — the case that used to fail outright;
* `findInvite_same_room` — whatever the surrounding noise, the joiner
  lands in the room the inviter meant.
-/
import Mathlib
import RequestProject.Kant.Bytes
import RequestProject.Kant.Text
import RequestProject.Kant.Clipboard
import RequestProject.Kant.Rendezvous
import RequestProject.Kant.SiteCard
import RequestProject.Kant.InviteCard

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.Join

open Kant Kant.Bytes Kant.Text Kant.Clipboard Kant.Rendezvous Kant.SiteCard

/-! ## The alphabet of a code -/

/-- A character a code can contain: a lowercase hex digit, or the field
separator `':'`. -/
def isCodeChar (c : Char) : Bool := (hexVal c).isSome || c == sep

/-- A character that ends a word: any whitespace a chat window might
wrap a link in. -/
def isBlank (c : Char) : Bool := c == ' ' || c == '\n' || c == '\t' || c == '\r'

/-- Text with no whitespace in it. -/
def BlankFree (s : List Char) : Prop := ∀ c ∈ s, isBlank c = false

/-- Text made only of code characters. -/
def AllCode (s : List Char) : Prop := ∀ c ∈ s, isCodeChar c = true

/-- Text with no code character in it: the punctuation a chat window
glues to a link. -/
def NoCode (s : List Char) : Prop := ∀ c ∈ s, isCodeChar c = false

theorem isCodeChar_ne_hash {c : Char} (h : isCodeChar c = true) : c ≠ Kant.Clipboard.hash := by
  rintro rfl
  exact absurd h (by decide)

theorem isCodeChar_not_blank {c : Char} (h : isCodeChar c = true) : isBlank c = false := by
  by_contra hb
  simp only [isBlank, Bool.not_eq_false, Bool.or_eq_true, beq_iff_eq] at hb
  rcases hb with ((rfl | rfl) | rfl) | rfl <;> exact absurd h (by decide)

theorem allCode_blankFree {s : List Char} (h : AllCode s) : BlankFree s :=
  fun c hc => isCodeChar_not_blank (h c hc)

theorem allCode_no_hash {s : List Char} (h : AllCode s) : Kant.Clipboard.hash ∉ s :=
  fun hc => isCodeChar_ne_hash (h _ hc) rfl

/-! ### Every code is written in that alphabet -/

theorem mem_hexEncode_isCodeChar {c : Char} {bs : Blob} (h : c ∈ hexEncode bs) :
    isCodeChar c = true := by
  simp only [hexEncode, List.mem_flatMap] at h
  obtain ⟨b, _, hcb⟩ := h
  have hb : b.toNat < 256 := b.toNat_lt_size
  have h1 : b.toNat / 16 < 16 := by omega
  have h2 : b.toNat % 16 < 16 := Nat.mod_lt _ (by norm_num)
  simp only [hexByte, List.mem_cons, List.not_mem_nil, or_false] at hcb
  have hdig : ∀ n, n < 16 → isCodeChar (hexDigit n) = true := by
    intro n hn; interval_cases n <;> decide
  rcases hcb with rfl | rfl
  · exact hdig _ h1
  · exact hdig _ h2

theorem mem_joinFields {c : Char} {fs : List (List Char)} (h : c ∈ joinFields fs) :
    c = sep ∨ ∃ f ∈ fs, c ∈ f := by
  induction fs with
  | nil => simp [joinFields] at h
  | cons f fs ih =>
      cases fs with
      | nil => exact Or.inr ⟨f, by simp, by simpa [joinFields] using h⟩
      | cons g gs =>
          rw [show joinFields (f :: g :: gs) = f ++ sep :: joinFields (g :: gs) from rfl] at h
          simp only [List.mem_append, List.mem_cons] at h
          rcases h with h | rfl | h
          · exact Or.inr ⟨f, by simp, h⟩
          · exact Or.inl rfl
          · rcases ih h with h | ⟨f', hf', hc⟩
            · exact Or.inl h
            · exact Or.inr ⟨f', by simp [hf'], hc⟩

/-- **A code is written entirely in the code alphabet**, which is what
lets its ends be trimmed of anything else. -/
theorem allCode_encode (e : Envelope) : AllCode e.encode := by
  intro c hc
  rcases mem_joinFields hc with rfl | ⟨f, hf, hcf⟩
  · decide
  · simp only [List.mem_map] at hf
    obtain ⟨b, _, rfl⟩ := hf
    exact mem_hexEncode_isCodeChar hcf

theorem allCode_copyInvite (i : Invite) : AllCode (copyInvite i) := allCode_encode _

theorem copyInvite_ne_nil (i : Invite) : copyInvite i ≠ [] := by
  intro h
  have htag : (hexEncode (ofInvite i).tag).length = 16 := by rfl
  have hpre : hexEncode (ofInvite i).tag <+: copyInvite i := by
    unfold copyInvite Envelope.encode
    cases hf : (ofInvite i).fields with
    | nil => simp [joinFields]
    | cons g gs =>
        refine ⟨sep :: joinFields ((g :: gs).map hexEncode), ?_⟩
        simp [joinFields]
  have hlen := hpre.length_le
  rw [h] at hlen
  simp [htag] at hlen

/-! ## Cutting the pasted text into words -/

/-- Every whitespace character rewritten as a space, so words are cut at
one delimiter. -/
def deblank (s : List Char) : List Char := s.map (fun c => if isBlank c then ' ' else c)

/-- The words of a piece of text. -/
def words (s : List Char) : List (List Char) :=
  (Kant.SiteCard.splitCh ' ' (deblank s)).filter (fun w => !w.isEmpty)

theorem splitCh_append_general (d : Char) (a b : List Char) :
    Kant.SiteCard.splitCh d (a ++ d :: b) =
      Kant.SiteCard.splitCh d a ++ Kant.SiteCard.splitCh d b := by
  induction a with
  | nil => simp [Kant.SiteCard.splitCh]
  | cons c cs ih =>
      by_cases hc : c = d
      · subst hc
        simp [Kant.SiteCard.splitCh, ih]
      · rw [List.cons_append, Kant.SiteCard.splitCh, if_neg hc, ih,
          Kant.SiteCard.splitCh, if_neg hc]
        cases hs : Kant.SiteCard.splitCh d cs with
        | nil => exact absurd hs (Kant.SiteCard.splitCh_ne_nil d cs)
        | cons f fs => simp

theorem deblank_append (a b : List Char) : deblank (a ++ b) = deblank a ++ deblank b := by
  simp [deblank]

theorem deblank_blank {b : Char} (h : isBlank b = true) : deblank [b] = [' '] := by
  simp [deblank, h]

theorem deblank_of_blankFree {s : List Char} (h : BlankFree s) : deblank s = s := by
  induction s with
  | nil => rfl
  | cons c cs ih =>
      have hc : isBlank c = false := h c (by simp)
      have hrest := ih (fun x hx => h x (by simp [hx]))
      unfold deblank at hrest ⊢
      simp [hc, hrest]

/-- **Words split at whitespace.** -/
theorem words_append_blank (a b : List Char) {sp : Char} (hsp : isBlank sp = true) :
    words (a ++ sp :: b) = words a ++ words b := by
  unfold words
  rw [show a ++ sp :: b = a ++ [sp] ++ b by simp, deblank_append, deblank_append,
    deblank_blank hsp]
  rw [show deblank a ++ [' '] ++ deblank b = deblank a ++ ' ' :: deblank b by simp,
    splitCh_append_general, List.filter_append]

/-- A blank-free, non-empty piece of text is one word. -/
theorem words_of_blankFree {s : List Char} (h : BlankFree s) (hne : s ≠ []) : words s = [s] := by
  have hsp : ' ' ∉ s := by
    intro hmem
    have := h ' ' hmem
    simp [isBlank] at this
  unfold words
  rw [deblank_of_blankFree h, Kant.SiteCard.splitCh_of_not_mem hsp]
  simp [hne]

theorem words_nil : words [] = [] := by decide

theorem words_of_blank {s : List Char} (h : ∀ c ∈ s, isBlank c = true) : words s = [] := by
  induction s with
  | nil => rfl
  | cons c cs ih =>
      have hc : isBlank c = true := h c (by simp)
      have hrest := ih (fun x hx => h x (by simp [hx]))
      rw [show c :: cs = [] ++ c :: cs from rfl, words_append_blank [] cs hc, hrest]
      simp [words_nil]

/-! ## Reading one word -/

/-- Everything after the last `'#'`: the fragment of a link, or the
whole word when there is no `'#'` at all. -/
def afterLastHash (w : List Char) : List Char :=
  (w.reverse.takeWhile (fun c => c ≠ Kant.Clipboard.hash)).reverse

/-- Trim from both ends anything that cannot occur inside a code. -/
def codePart (w : List Char) : List Char :=
  ((afterLastHash w).dropWhile (fun c => !isCodeChar c)).takeWhile isCodeChar

/-- Read one word as an invitation. -/
def wordInvite (w : List Char) : Option Invite := pasteInvite (codePart w)

/-- **Find the invitation in whatever was pasted or scanned.** -/
def findInvite (s : List Char) : Option Invite := (words s).findSome? wordInvite

theorem takeWhile_append_none {p : Char → Bool} {a b : List Char}
    (ha : ∀ c ∈ a, p c = true) (hb : ∀ c ∈ b, p c = false) : (a ++ b).takeWhile p = a := by
  induction a with
  | nil =>
      cases b with
      | nil => rfl
      | cons c cs => simp [List.takeWhile_cons_of_neg, hb c (by simp)]
  | cons c cs ih =>
      rw [List.cons_append, List.takeWhile_cons_of_pos (ha c (by simp)),
        ih (fun x hx => ha x (by simp [hx]))]

theorem afterLastHash_append {pre x : List Char} (hx : Kant.Clipboard.hash ∉ x) :
    afterLastHash (pre ++ Kant.Clipboard.hash :: x) = x := by
  unfold afterLastHash
  rw [List.reverse_append, List.reverse_cons]
  rw [show x.reverse ++ [Kant.Clipboard.hash] ++ pre.reverse =
      x.reverse ++ Kant.Clipboard.hash :: pre.reverse by simp]
  rw [Kant.SiteCard.takeWhile_append_sep (p := fun c => c ≠ Kant.Clipboard.hash)
    (a := x.reverse) (b := pre.reverse) ?_ (by decide)]
  · simp
  · intro c hc
    have : c ≠ Kant.Clipboard.hash := by
      rintro rfl
      exact hx (List.mem_reverse.mp hc)
    simpa using this

theorem afterLastHash_of_no_hash {w : List Char} (h : Kant.Clipboard.hash ∉ w) :
    afterLastHash w = w := by
  rw [show w = [] ++ w from rfl] at h ⊢
  unfold afterLastHash
  rw [List.nil_append] at h ⊢
  have : w.reverse.takeWhile (fun c => c ≠ Kant.Clipboard.hash) = w.reverse := by
    refine List.takeWhile_eq_self_iff.mpr ?_
    intro c hc
    have : c ≠ Kant.Clipboard.hash := by
      rintro rfl
      exact h (List.mem_reverse.mp hc)
    simpa using this
  rw [this, List.reverse_reverse]

/-- **Junk glued to either end of a link does not hide it.**  Whatever
comes before the fragment marker, and whatever punctuation is stuck to
the end, the invitation is still the one that was sent. -/
theorem codePart_junk {pre x post : List Char} (hx : AllCode x) (hxne : x ≠ [])
    (hhash : Kant.Clipboard.hash ∉ post) (hpost : NoCode post) :
    codePart (pre ++ Kant.Clipboard.hash :: (x ++ post)) = x := by
  have hxh : Kant.Clipboard.hash ∉ x ++ post := by
    simp only [List.mem_append, not_or]
    exact ⟨allCode_no_hash hx, hhash⟩
  unfold codePart
  rw [afterLastHash_append hxh]
  cases hxc : x with
  | nil => exact absurd hxc hxne
  | cons c cs =>
      have hc : isCodeChar c = true := hx c (by rw [hxc]; simp)
      rw [List.cons_append, List.dropWhile_cons_of_neg (by simp [hc]), ← List.cons_append,
        ← hxc]
      exact takeWhile_append_none hx hpost

/-- The same for a bare code with no link around it. -/
theorem codePart_bare {x post : List Char} (hx : AllCode x) (hxne : x ≠ [])
    (hhash : Kant.Clipboard.hash ∉ post) (hpost : NoCode post) :
    codePart (x ++ post) = x := by
  have hxh : Kant.Clipboard.hash ∉ x ++ post := by
    simp only [List.mem_append, not_or]
    exact ⟨allCode_no_hash hx, hhash⟩
  unfold codePart
  rw [afterLastHash_of_no_hash hxh]
  cases hxc : x with
  | nil => exact absurd hxc hxne
  | cons c cs =>
      have hc : isCodeChar c = true := hx c (by rw [hxc]; simp)
      rw [List.cons_append, List.dropWhile_cons_of_neg (by simp [hc]), ← List.cons_append,
        ← hxc]
      exact takeWhile_append_none hx hpost

/-- **One word carrying the link reads back as the invitation**, however
it is dressed: `<https://kant.example/#…>,` is still that invitation. -/
theorem wordInvite_junk {c : Config} {i : Invite} (hi : i.Wire)
    {lead trail : List Char} (hhash : Kant.Clipboard.hash ∉ trail) (htrail : NoCode trail) :
    wordInvite (lead ++ Kant.InviteCard.inviteUrl c i ++ trail) = some i := by
  have hurl : lead ++ Kant.InviteCard.inviteUrl c i ++ trail =
      (lead ++ c.origin) ++ Kant.Clipboard.hash :: (copyInvite i ++ trail) := by
    rw [Kant.InviteCard.inviteUrl_eq]; simp
  rw [wordInvite, hurl,
    codePart_junk (allCode_copyInvite i) (copyInvite_ne_nil i) hhash htrail,
    pasteInvite_copyInvite hi]

/-- A bare code, with punctuation glued to it, still reads. -/
theorem wordInvite_code {i : Invite} (hi : i.Wire) {trail : List Char}
    (hhash : Kant.Clipboard.hash ∉ trail) (htrail : NoCode trail) :
    wordInvite (copyInvite i ++ trail) = some i := by
  rw [wordInvite, codePart_bare (allCode_copyInvite i) (copyInvite_ne_nil i) hhash htrail,
    pasteInvite_copyInvite hi]

/-! ## Finding it in a whole message -/

theorem findInvite_append_blank (a b : List Char) {sp : Char} (hsp : isBlank sp = true) :
    findInvite (a ++ sp :: b) = (findInvite a).or (findInvite b) := by
  unfold findInvite
  rw [words_append_blank a b hsp, List.findSome?_append]

theorem findInvite_of_word {w : List Char} (hw : BlankFree w) (hne : w ≠ []) :
    findInvite w = wordInvite w := by
  unfold findInvite
  rw [words_of_blankFree hw hne]
  simp

theorem blankFree_inviteUrl {c : Config} (h : BlankFree c.origin) (i : Invite) :
    BlankFree (Kant.InviteCard.inviteUrl c i) := by
  intro ch hch
  rw [Kant.InviteCard.inviteUrl_eq] at hch
  simp only [List.mem_append, List.mem_cons] at hch
  rcases hch with hch | rfl | hch
  · exact h ch hch
  · decide
  · exact isCodeChar_not_blank (allCode_copyInvite i ch hch)

/-- **The plain link joins the room.** -/
theorem findInvite_inviteUrl {c : Config} (ho : BlankFree c.origin)
    {i : Invite} (hi : i.Wire) :
    findInvite (Kant.InviteCard.inviteUrl c i) = some i := by
  have hne : Kant.InviteCard.inviteUrl c i ≠ [] := by
    intro h
    have := congrArg List.length h
    rw [Kant.InviteCard.inviteUrl_length] at this
    simp at this
  rw [findInvite_of_word (blankFree_inviteUrl ho i) hne,
    show Kant.InviteCard.inviteUrl c i = [] ++ Kant.InviteCard.inviteUrl c i ++ [] by simp,
    wordInvite_junk hi (by simp) (by intro x hx; simp at hx)]

/-- **The bare code still joins the room**, for anyone who copied the
code rather than the link. -/
theorem findInvite_copyInvite {i : Invite} (hi : i.Wire) :
    findInvite (copyInvite i) = some i := by
  rw [findInvite_of_word (allCode_blankFree (allCode_copyInvite i)) (copyInvite_ne_nil i),
    show copyInvite i = copyInvite i ++ [] by simp,
    wordInvite_code hi (by simp) (by intro x hx; simp at hx)]

/-- **A link pasted inside a message still joins the room.**  Text
before it, text after it, brackets around it and a full stop behind it:
the invitation that comes out is the one that was sent. -/
theorem findInvite_in_message {c : Config} (ho : BlankFree c.origin)
    {i : Invite} (hi : i.Wire) {before after lead trail : List Char}
    (hbefore : findInvite before = none)
    (hlead : BlankFree lead) (htrailB : BlankFree trail)
    (hhash : Kant.Clipboard.hash ∉ trail) (htrail : NoCode trail)
    {sp sq : Char} (hsp : isBlank sp = true) (hsq : isBlank sq = true) :
    findInvite (before ++ sp :: ((lead ++ Kant.InviteCard.inviteUrl c i ++ trail) ++
      sq :: after)) = some i := by
  have hword : BlankFree (lead ++ Kant.InviteCard.inviteUrl c i ++ trail) := by
    intro ch hch
    rcases List.mem_append.mp hch with h1 | h1
    · rcases List.mem_append.mp h1 with h2 | h2
      · exact hlead ch h2
      · exact blankFree_inviteUrl ho i ch h2
    · exact htrailB ch h1
  have hne : lead ++ Kant.InviteCard.inviteUrl c i ++ trail ≠ [] := by
    intro h
    have hmem : (Kant.InviteCard.inviteUrl c i) = [] := by
      have := congrArg List.length h
      simp only [List.length_append, List.length_nil] at this
      exact List.eq_nil_of_length_eq_zero (by omega)
    have := congrArg List.length hmem
    rw [Kant.InviteCard.inviteUrl_length] at this
    simp at this
  rw [findInvite_append_blank _ _ hsp, hbefore, findInvite_append_blank _ _ hsq,
    findInvite_of_word hword hne, wordInvite_junk hi hhash htrail]
  rfl

/-- **The case that used to fail outright**: a link with a newline after
it, exactly as a chat window hands it over. -/
theorem findInvite_trailing_newline {c : Config} (ho : BlankFree c.origin)
    {i : Invite} (hi : i.Wire) :
    findInvite (Kant.InviteCard.inviteUrl c i ++ ['\n']) = some i := by
  rw [show Kant.InviteCard.inviteUrl c i ++ ['\n'] =
      Kant.InviteCard.inviteUrl c i ++ '\n' :: [] by simp,
    findInvite_append_blank _ _ (by decide), findInvite_inviteUrl ho hi]
  rfl

/-- **Whatever the noise, the joiner lands in the inviter's room.** -/
theorem message_same_room {c : Config} (ho : BlankFree c.origin)
    {i : Invite} (hi : i.Wire) {before after lead trail : List Char}
    (hbefore : findInvite before = none)
    (hlead : BlankFree lead) (htrailB : BlankFree trail)
    (hhash : Kant.Clipboard.hash ∉ trail) (htrail : NoCode trail)
    {sp sq : Char} (hsp : isBlank sp = true) (hsq : isBlank sq = true) :
    (findInvite (before ++ sp :: ((lead ++ Kant.InviteCard.inviteUrl c i ++ trail) ++
      sq :: after))).map Invite.room = some i.room := by
  rw [findInvite_in_message ho hi hbefore hlead htrailB hhash htrail hsp hsq]
  rfl

end Kant.Join
