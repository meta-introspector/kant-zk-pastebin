/-
# The feed: seeing the posts

The store (`Kant.Paste`) is content addressed and unordered.  A reader
wants something else: a *feed* — rows they can read, ordered newest
first, searchable, paginated, grouped into threads, and each row
carrying the exact text needed to copy the post back out again.

Proved here:

* `view_resolves` — every row displayed really is a post the store
  answers to, at the address the row advertises: the feed cannot show
  something that is not there, nor mislabel it;
* `row_title_recoverable` / `row_body_recoverable` — the rendered row is
  lossless: the reader can recover the original title and content from
  what is on screen;
* `row_no_markup` — a rendered row can never break out of its element,
  so a post cannot inject markup into the feed;
* `row_copy_roundTrip` — the copy button on a row yields text that pastes
  back into exactly that post;
* `paginate_flatten` / `paginate_length_le` — paging through the feed
  shows every post exactly once, and no page exceeds the page size;
* `mem_search_iff` — search returns exactly the posts containing the
  phrase, in feed order;
* `thread_sound` / `mem_replies_iff` — a thread view contains the root
  and precisely its replies;
* `newest_perm` / `newest_sorted` — sorting the feed reorders it without
  adding or dropping a post, and the result really is ordered.
-/
import Mathlib
import RequestProject.Kant.Bytes
import RequestProject.Kant.Text
import RequestProject.Kant.Erdfa
import RequestProject.Kant.Paste
import RequestProject.Kant.Clipboard

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.Feed

open Kant Kant.Bytes Kant.Text

/-! ## Rows -/

/-- One rendered row of the feed: what the reader sees for a post, plus
the clipboard text that reproduces it. -/
structure Row where
  /-- The content witness (the address shown under the post). -/
  witness : List Char
  /-- The DASL content address. -/
  cid : Nat
  /-- The title, escaped for embedding in HTML. -/
  title : List Char
  /-- The body, escaped for embedding in HTML. -/
  body : List Char
  /-- The timestamp as posted. -/
  timestamp : List Char
  /-- The post this one replies to, if any. -/
  replyTo : Option (List Char)
  /-- Size of the content in bytes. -/
  bytes : Nat
  /-- The clipboard text of the post: what the copy button puts on the
  clipboard. -/
  copy : List Char
deriving DecidableEq, Repr

/-- Render a post as a feed row. -/
def row (p : Paste) : Row :=
  { witness := p.witness
    cid := p.cid
    title := Kant.Erdfa.escape p.title
    body := Kant.Erdfa.escape (asciiChars p.content)
    timestamp := p.timestamp
    replyTo := p.replyTo
    bytes := p.content.length
    copy := Kant.Clipboard.copyText p }

/-- The posts held by a store, most recently added first. -/
def feed (st : Store) : List Paste := st.entries

/-- The rendered feed. -/
def view (st : Store) : List Row := (feed st).map row

@[simp] theorem view_length (st : Store) : (view st).length = (feed st).length := by
  simp [view]

/-- Every post in the feed is answered by the store, under the very
address its row displays. -/
theorem feed_resolves {st : Store} {p : Paste} (h : p ∈ feed st) :
    (st.get p.witness).isSome := by
  rcases hopt : st.get p.witness with _ | q
  · rw [Store.get, List.find?_eq_none] at hopt
    exact absurd (beq_self_eq_true p.witness) (hopt p h)
  · rfl

/-- **The feed shows only what the store has.**  Every row on screen
comes from a post the store answers to at the row's own address. -/
theorem view_resolves {st : Store} {r : Row} (h : r ∈ view st) :
    ∃ p ∈ feed st, r = row p ∧ (st.get r.witness).isSome := by
  simp only [view, List.mem_map] at h
  obtain ⟨p, hp, rfl⟩ := h
  exact ⟨p, hp, rfl, feed_resolves hp⟩

/-- The title on screen still determines the title that was posted. -/
theorem row_title_recoverable (p : Paste) : Kant.Erdfa.unescape (row p).title = p.title :=
  Kant.Erdfa.escape_unescape_id _

/-- The body on screen still determines the content that was posted. -/
theorem row_body_recoverable {p : Paste} (h : BytesAscii p.content) :
    asciiBytes (Kant.Erdfa.unescape (row p).body) = p.content := by
  rw [show (row p).body = Kant.Erdfa.escape (asciiChars p.content) from rfl,
    Kant.Erdfa.escape_unescape_id, asciiBytes_asciiChars h]

/-- **A post cannot inject markup into the feed.** -/
theorem row_no_markup (p : Paste) :
    ('<' ∉ (row p).title ∧ '>' ∉ (row p).title ∧ '"' ∉ (row p).title) ∧
    ('<' ∉ (row p).body ∧ '>' ∉ (row p).body ∧ '"' ∉ (row p).body) :=
  ⟨Kant.Erdfa.escape_no_markup _, Kant.Erdfa.escape_no_markup _⟩

/-- **The copy button is faithful.**  The text a row offers for copying
pastes back as exactly that post. -/
theorem row_copy_roundTrip {p : Paste} (h : Kant.Clipboard.Copyable p) :
    Kant.Clipboard.pasteText (row p).copy = some p :=
  Kant.Clipboard.pasteText_copyText h

/-- The result summary displayed beside a row. -/
def rowReceipt (p : Paste) (credits : Nat) : Kant.Clipboard.Receipt :=
  Kant.Clipboard.receiptOf p credits

/-- **The displayed results copy and paste back exactly.** -/
theorem rowReceipt_copy_roundTrip (p : Paste) (credits : Nat) :
    Kant.Clipboard.pasteReceipt (Kant.Clipboard.copyReceipt (rowReceipt p credits)) =
      some (rowReceipt p credits) :=
  Kant.Clipboard.pasteReceipt_copyReceipt_of_paste p credits

/-! ## Pagination -/

/-- Split a feed into pages of at most `size` entries. -/
def paginate {α : Type} (size : Nat) (xs : List α) : List (List α) :=
  if size = 0 then []
  else if xs.isEmpty then []
  else xs.take size :: paginate size (xs.drop size)
  termination_by xs.length
  decreasing_by
    rename_i hsize hempty
    have hpos : 0 < xs.length := by
      simpa [List.isEmpty_iff, List.length_pos_iff] using hempty
    simp only [List.length_drop]
    omega

/-- **Paging shows every post exactly once, in order.** -/
theorem paginate_flatten {α : Type} {size : Nat} (h : 0 < size) (xs : List α) :
    (paginate size xs).flatten = xs := by
  induction xs using paginate.induct size with
  | case1 => omega
  | case2 xs _ hempty =>
      rw [paginate, if_neg (by omega), if_pos hempty]
      simpa using (List.isEmpty_iff.mp hempty).symm
  | case3 xs hz hempty ih =>
      rw [paginate, if_neg hz, if_neg hempty]
      simp only [List.flatten_cons, ih]
      exact List.take_append_drop size xs

/-- No page is bigger than the page size. -/
theorem paginate_length_le {α : Type} {size : Nat} (xs : List α) :
    ∀ pg ∈ paginate size xs, pg.length ≤ size := by
  induction xs using paginate.induct size with
  | case1 xs hz => intro pg hpg; rw [paginate, if_pos hz] at hpg; simp at hpg
  | case2 xs hz hempty =>
      intro pg hpg; rw [paginate, if_neg hz, if_pos hempty] at hpg; simp at hpg
  | case3 xs hz hempty ih =>
      intro pg hpg
      rw [paginate, if_neg hz, if_neg hempty, List.mem_cons] at hpg
      rcases hpg with rfl | hpg
      · simp
      · exact ih pg hpg

/-- No empty page is ever emitted. -/
theorem paginate_length_pos {α : Type} {size : Nat} (xs : List α) :
    ∀ pg ∈ paginate size xs, 0 < pg.length := by
  induction xs using paginate.induct size with
  | case1 xs hz => intro pg hpg; rw [paginate, if_pos hz] at hpg; simp at hpg
  | case2 xs hz hempty =>
      intro pg hpg; rw [paginate, if_neg hz, if_pos hempty] at hpg; simp at hpg
  | case3 xs hz hempty ih =>
      intro pg hpg
      rw [paginate, if_neg hz, if_neg hempty, List.mem_cons] at hpg
      rcases hpg with rfl | hpg
      · have hpos : 0 < xs.length := by
          simpa [List.isEmpty_iff, List.length_pos_iff] using hempty
        simp only [List.length_take]
        omega
      · exact ih pg hpg

/-- The `n`-th page of a feed. -/
def page {α : Type} (size n : Nat) (xs : List α) : List α := (xs.drop (size * n)).take size

/-! ## Search -/

/-- Does a post mention the phrase, in its title or its body? -/
def mentions (q : List Char) (p : Paste) : Bool :=
  containsSub q p.title || containsSub q (asciiChars p.content)

/-- Search the feed. -/
def search (q : List Char) (ps : List Paste) : List Paste := ps.filter (mentions q)

/-- Search never invents a post: results are a sublist of the feed, so
they keep feed order too. -/
theorem search_sublist (q : List Char) (ps : List Paste) : (search q ps).Sublist ps :=
  List.filter_sublist

/-- **Search is exactly containment.**  A post is in the results iff it
is in the feed and mentions the phrase, as a contiguous phrase, in its
title or body. -/
theorem mem_search_iff {q : List Char} {ps : List Paste} {p : Paste} :
    p ∈ search q ps ↔ p ∈ ps ∧ (q <:+: p.title ∨ q <:+: asciiChars p.content) := by
  rw [search, List.mem_filter]
  constructor
  · rintro ⟨hp, hm⟩
    refine ⟨hp, ?_⟩
    rcases Bool.or_eq_true _ _ |>.mp hm with h | h
    · exact Or.inl ((containsSub_iff_infix _ _).mp h)
    · exact Or.inr ((containsSub_iff_infix _ _).mp h)
  · rintro ⟨hp, h⟩
    refine ⟨hp, ?_⟩
    rcases h with h | h
    · simp [mentions, (containsSub_iff_infix _ _).mpr h]
    · simp [mentions, (containsSub_iff_infix _ _).mpr h]

/-! ## Threads -/

/-- The replies to a post, in feed order. -/
def replies (w : List Char) (ps : List Paste) : List Paste :=
  ps.filter (fun p => p.replyTo == some w)

/-- A thread view: the root post followed by its direct replies. -/
def thread (root : Paste) (ps : List Paste) : List Paste :=
  root :: replies root.witness ps

theorem replies_sublist (w : List Char) (ps : List Paste) : (replies w ps).Sublist ps :=
  List.filter_sublist

/-- **A thread contains precisely the replies to its root.** -/
theorem mem_replies_iff {w : List Char} {ps : List Paste} {p : Paste} :
    p ∈ replies w ps ↔ p ∈ ps ∧ p.replyTo = some w := by
  simp [replies, List.mem_filter]

/-- Everything below the root of a thread really is a reply to it. -/
theorem thread_sound {root p : Paste} {ps : List Paste}
    (h : p ∈ thread root ps) (hne : p ≠ root) : p.replyTo = some root.witness := by
  rcases List.mem_cons.mp h with rfl | h
  · exact absurd rfl hne
  · exact (mem_replies_iff.mp h).2

/-- The root of a thread is always shown. -/
theorem root_mem_thread (root : Paste) (ps : List Paste) : root ∈ thread root ps := by
  simp [thread]

/-! ## Ordering -/

/-- The numeric ordering key of a post: the digits of its timestamp. -/
def timeKey (p : Paste) : Nat := digitsValue p.timestamp

/-- Sort a feed newest first. -/
def newest (ps : List Paste) : List Paste :=
  ps.mergeSort (fun a b => timeKey b ≤ timeKey a)

/-- **Sorting neither adds nor drops a post.** -/
theorem newest_perm (ps : List Paste) : (newest ps).Perm ps :=
  List.mergeSort_perm ps _

@[simp] theorem newest_length (ps : List Paste) : (newest ps).length = ps.length :=
  (newest_perm ps).length_eq

/-- Sorting preserves membership. -/
theorem mem_newest_iff {ps : List Paste} {p : Paste} : p ∈ newest ps ↔ p ∈ ps :=
  (newest_perm ps).mem_iff

/-- **The sorted feed really is ordered**, newest timestamp first. -/
theorem newest_sorted (ps : List Paste) :
    List.Pairwise (fun a b => timeKey b ≤ timeKey a) (newest ps) := by
  have htrans : ∀ a b c : Paste, (decide (timeKey b ≤ timeKey a)) = true →
      (decide (timeKey c ≤ timeKey b)) = true → (decide (timeKey c ≤ timeKey a)) = true := by
    intro a b c hab hbc
    simp only [decide_eq_true_eq] at *
    omega
  have htotal : ∀ a b : Paste,
      ((decide (timeKey b ≤ timeKey a)) || (decide (timeKey a ≤ timeKey b))) = true := by
    intro a b
    simp only [Bool.or_eq_true, decide_eq_true_eq]
    omega
  simpa using List.pairwise_mergeSort htrans htotal ps

/-- The feed a reader actually gets: newest first, optionally filtered by
a search phrase, cut into pages. -/
def timeline (st : Store) (q : List Char) (size : Nat) : List (List Row) :=
  paginate size ((search q (newest (feed st))).map row)

/-- **A timeline shows each matching post exactly once.** -/
theorem timeline_flatten {st : Store} {q : List Char} {size : Nat} (h : 0 < size) :
    (timeline st q size).flatten = (search q (newest (feed st))).map row :=
  paginate_flatten h _

/-- Every page of a timeline respects the page size. -/
theorem timeline_page_size {st : Store} {q : List Char} {size : Nat} :
    ∀ pg ∈ timeline st q size, pg.length ≤ size :=
  paginate_length_le _

end Kant.Feed
