/-
# Share the log, and post it to the store

`Kant.Diagnostics` builds the run and knows how to withhold the room
secret from it (`Log.share`).  This module is the button on top of that:
**Share the log** — take the run as it stands, filter it, and hand it
over as one of three things:

* the *text*, for a chat window or a bug report (`logText`);
* a *post* in the content-addressed store, so the run gets a witness, a
  page and a link like everything else the app holds (`logPaste`,
  `postLog`);
* a *thread of numbered chat messages*, each inside a tweet, for the
  case where there is no server at all and the only transport is a human
  pasting text into a conversation (`chatParts`).

Everything proved here is about those three, and about the one property
that matters more than any of them: **a shared run never quotes a
secret** (`shared_no_secret`, `posted_no_secret`).
-/
import Mathlib
import RequestProject.Kant.Diagnostics
import RequestProject.Kant.Feed
import RequestProject.Kant.Uucp

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.ShareLog

open Kant Kant.Bytes Kant.Text Kant.Clipboard Kant.Connectivity Kant.Diagnostics
open Kant.Sneakernet Kant.Uucp

/-! ## The run, made shareable -/

/-- What the **Share the log** button hands over: the verdict, the room's
eight-character handle (never the room), the relay in use, and every
event of the run that quotes none of the secrets held. -/
def shareReport (secrets : List (List Char)) (v : Verdict) (room relay : List Char)
    (l : Log) : Report :=
  ⟨v, Diagnostics.ref room, relay, (l.share secrets).events⟩

/-- The room never travels: what goes out is its eight-character handle. -/
@[simp] theorem shareReport_room_length {secrets : List (List Char)} {v : Verdict}
    {room relay : List Char} {l : Log} :
    (shareReport secrets v room relay l).room.length = 8 :=
  Diagnostics.ref_length room

/-- **The room itself is not in a shared run.**  Any room longer than the
handle is provably not the handle. -/
theorem shareReport_room_ne {secrets : List (List Char)} {v : Verdict}
    {room relay : List Char} {l : Log} (h : 8 < room.length) :
    (shareReport secrets v room relay l).room ≠ room :=
  Diagnostics.ref_ne h

/-- **Nothing shared quotes a secret**, neither as a sentence nor as a
detail. -/
theorem shared_no_secret {secrets : List (List Char)} {v : Verdict}
    {room relay : List Char} {l : Log} {e : Event}
    (he : e ∈ (shareReport secrets v room relay l).events) {s : List Char} (hs : s ∈ secrets) :
    ¬ (s <:+: e.text) ∧ ¬ (s <:+: e.detail) :=
  Diagnostics.share_no_secret he hs

/-- **Nothing else is withheld**: an event of the run that quotes no
secret is in the shared report as it stands. -/
theorem shared_keeps {secrets : List (List Char)} {v : Verdict}
    {room relay : List Char} {l : Log} {e : Event}
    (he : e ∈ l.events) (hc : e.clean secrets = true) :
    e ∈ (shareReport secrets v room relay l).events :=
  Diagnostics.share_keeps he hc

/-- Sharing never invents an event. -/
theorem shared_sublist {secrets : List (List Char)} {v : Verdict}
    {room relay : List Char} {l : Log} :
    (shareReport secrets v room relay l).events.Sublist l.events :=
  List.filter_sublist ..

/-! ## As text -/

/-- The text the button puts on the clipboard. -/
def logText (r : Report) : List Char := renderReport r

/-- **A shared run reads back as the same run.** -/
theorem logText_roundTrip {r : Report} (h : r.Wire) : parseReport (logText r) = some r :=
  parseReport_renderReport h

/-- Joined lines are ASCII when the lines are: a newline is ASCII too. -/
theorem isAscii_joinLines {ls : List (List Char)} (h : ∀ l ∈ ls, IsAscii l) :
    IsAscii (joinLines ls) := by
  induction ls with
  | nil => intro c hc; simp [joinLines] at hc
  | cons l ls ih =>
      cases ls with
      | nil => simpa [joinLines] using h l (by simp)
      | cons g gs =>
          have hrest : IsAscii (joinLines (g :: gs)) :=
            ih (fun x hx => h x (List.mem_cons_of_mem _ hx))
          intro c hc
          rw [show joinLines (l :: g :: gs) = l ++ '\n' :: joinLines (g :: gs) from rfl] at hc
          rcases List.mem_append.mp hc with hc | hc
          · exact h l (by simp) c hc
          · rcases List.mem_cons.mp hc with rfl | hc
            · decide
            · exact hrest c hc

/-- **A shared run is plain ASCII**, so it goes through any chat window,
any bug tracker and any QR code unchanged. -/
theorem isAscii_logText (r : Report) : IsAscii (logText r) := by
  refine isAscii_joinLines ?_
  intro x hx
  rcases List.mem_cons.mp hx with rfl | hx
  · exact Envelope.isAscii_encode _
  · obtain ⟨e, _, rfl⟩ := List.mem_map.mp hx
    exact Envelope.isAscii_encode _

/-! ## As a post in the store

The store is content-addressed (`Kant.Store`), so posting the run gives
it a witness, and therefore a page, a link and a QR code, exactly like
any other paste.  Nothing here needs a server: `put` is a list. -/

/-- The title a posted run carries. -/
def logTitle : List Char := "the run so far".toList

/-- The run as a post. -/
def logPaste (id ts : List Char) (r : Report) : Paste :=
  ⟨id, logTitle, asciiBytes (logText r), ts, none⟩

/-- **The posted run is the run.**  What the store holds parses back to
exactly the report that was shared. -/
theorem logPaste_content_roundTrip {id ts : List Char} {r : Report} (h : r.Wire) :
    parseReport (asciiChars (logPaste id ts r).content) = some r := by
  simp only [logPaste]
  rw [asciiChars_asciiBytes (isAscii_logText r)]
  exact logText_roundTrip h

/-- The address of a posted run is the digest of its text: two people who
share the same run post the same block. -/
theorem logPaste_witness {id ts : List Char} (r : Report) :
    (logPaste id ts r).witness = Kant.Bytes.witness (asciiBytes (logText r)) := rfl

/-- Two people whose runs came out the same post the very same block,
whatever they called it. -/
theorem logPaste_witness_congr {id₁ ts₁ id₂ ts₂ : List Char} {r₁ r₂ : Report}
    (h : logText r₁ = logText r₂) :
    (logPaste id₁ ts₁ r₁).witness = (logPaste id₂ ts₂ r₂).witness := by
  simp [logPaste_witness, h]

/-- **Post it to the store.** -/
def postLog (st : Store) (id ts : List Char) (r : Report) : Store :=
  st.put (logPaste id ts r)

/-- After posting, the run has an address that resolves. -/
theorem postLog_resolves (st : Store) (id ts : List Char) (r : Report) :
    ((postLog st id ts r).get (logPaste id ts r).witness).isSome :=
  Store.get_put_self st (logPaste id ts r)

/-- Posting the same run twice changes nothing. -/
theorem postLog_idem (st : Store) (id ts : List Char) (r : Report) :
    postLog (postLog st id ts r) id ts r = postLog st id ts r :=
  Store.put_idem st (logPaste id ts r)

/-- Posting a run never loses anything the store already held. -/
theorem postLog_monotone {st : Store} {w : List Char} (id ts : List Char) (r : Report)
    (h : st.has w) : (postLog st id ts r).has w :=
  Store.has_put_mono h

/-- Whatever the store answers with is the posted run itself. -/
theorem postLog_get {st : Store} {id ts : List Char} {r : Report}
    (hfresh : ¬ (st.get (logPaste id ts r).witness).isSome) :
    (postLog st id ts r).get (logPaste id ts r).witness = some (logPaste id ts r) :=
  Store.get_put_eq hfresh

/-- **A posted run shows up in the feed**, like any other post. -/
theorem postLog_in_feed {st : Store} {id ts : List Char} {r : Report}
    (hfresh : ¬ (st.get (logPaste id ts r).witness).isSome) :
    logPaste id ts r ∈ Kant.Feed.feed (postLog st id ts r) := by
  simp [Kant.Feed.feed, postLog, Store.put_new hfresh]

/-- **A posted run still quotes no secret.**  Filtering happens before
the post exists, so nothing the store holds can leak the room. -/
theorem posted_no_secret {secrets : List (List Char)} {v : Verdict}
    {room relay id ts : List Char} {l : Log}
    (hw : (shareReport secrets v room relay l).Wire) {r : Report}
    (hr : parseReport
        (asciiChars (logPaste id ts (shareReport secrets v room relay l)).content) = some r)
    {e : Event} (he : e ∈ r.events) {s : List Char} (hs : s ∈ secrets) :
    ¬ (s <:+: e.text) ∧ ¬ (s <:+: e.detail) := by
  rw [logPaste_content_roundTrip hw, Option.some.injEq] at hr
  subst hr
  exact shared_no_secret he hs

/-- A posted run cannot inject markup into the feed: the body is escaped
like every other body. -/
theorem postLog_row_no_markup (id ts : List Char) (r : Report) :
    ('<' ∉ (Kant.Feed.row (logPaste id ts r)).body ∧
      '>' ∉ (Kant.Feed.row (logPaste id ts r)).body ∧
      '"' ∉ (Kant.Feed.row (logPaste id ts r)).body) :=
  (Kant.Feed.row_no_markup _).2

/-- A posted run is copyable when its identifier and timestamp are
ASCII — which is what the app generates. -/
theorem copyable_logPaste {id ts : List Char} (hid : IsAscii id) (hts : IsAscii ts)
    (r : Report) : Kant.Clipboard.Copyable (logPaste id ts r) :=
  { id := hid
    title := by intro c hc; simp only [logPaste, logTitle] at hc; fin_cases hc <;> decide
    timestamp := hts
    replyTo := by intro s hs; simp [logPaste] at hs }

/-- **The posted run copies and pastes back exactly.** -/
theorem postLog_copy_roundTrip {id ts : List Char} (hid : IsAscii id) (hts : IsAscii ts)
    (r : Report) :
    Kant.Clipboard.pasteText (Kant.Clipboard.copyText (logPaste id ts r)) =
      some (logPaste id ts r) :=
  Kant.Clipboard.pasteText_copyText (copyable_logPaste hid hts r)

/-! ## As a thread of chat messages

The case with no server at all: the run goes out as numbered parts,
small enough for a tweet, which the other side collects in any order. -/

/-- The run cut into numbered chat messages of `limit` payload bytes. -/
def chatParts (limit : Nat) (r : Report) : List (List Char) := thread limit (logText r)

/-- Read a run back out of the messages that were pasted into the chat. -/
def readChatParts (parts : List (List Char)) : Option Report :=
  (readThread parts).bind parseReport

/-- **A run shared by hand through a chat arrives intact.** -/
theorem readChatParts_chatParts {limit : Nat} (hlim : 0 < limit) {r : Report} (h : r.Wire) :
    readChatParts (chatParts limit r) = some r := by
  unfold readChatParts chatParts
  rw [readThread_thread hlim (isAscii_logText r)]
  simpa using logText_roundTrip h

/-- **The messages may be pasted in any order.**  A chat scrolls, people
reply out of turn, screenshots arrive shuffled; the run still arrives. -/
theorem readChatParts_perm {limit : Nat} (hlim : 0 < limit) {r : Report} (h : r.Wire)
    {fs : List Frame} (hperm : (frames limit (asciiBytes (logText r))).Perm fs) :
    readChatParts (fs.map (fun f => (ofPart f).encode)) = some r := by
  unfold readChatParts
  rw [readThread_perm hlim (isAscii_logText r) hperm]
  simpa using logText_roundTrip h

/-- **Every chat message fits in a tweet.** -/
theorem chatParts_fit_tweet {r : Report}
    (hn : (chunk 100 (asciiBytes (logText r))).length < 256 ^ 3) :
    ∀ t ∈ chatParts 100 r, t.length ≤ Carrier.tweet.capacity :=
  thread_fits_tweet hn

/-- A chat message is plain text. -/
theorem isAscii_chatPart {limit : Nat} {r : Report} {t : List Char} (ht : t ∈ chatParts limit r) :
    IsAscii t := by
  obtain ⟨f, _, rfl⟩ := List.mem_map.mp ht
  exact Envelope.isAscii_encode _

/-- A run that arrives through the chat still quotes no secret: the parts
carry the filtered report, and nothing else. -/
theorem chat_no_secret {limit : Nat} (hlim : 0 < limit) {secrets : List (List Char)}
    {v : Verdict} {room relay : List Char} {l : Log}
    (h : (shareReport secrets v room relay l).Wire) {r : Report}
    (hr : readChatParts (chatParts limit (shareReport secrets v room relay l)) = some r)
    {e : Event} (he : e ∈ r.events) {s : List Char} (hs : s ∈ secrets) :
    ¬ (s <:+: e.text) ∧ ¬ (s <:+: e.detail) := by
  rw [readChatParts_chatParts hlim h, Option.some.injEq] at hr
  subst hr
  exact shared_no_secret he hs


/-! ## Golden vectors shared with the JavaScript

`web/sharelog-test.mjs` checks the transcription in `web/kant-sharelog.mjs`
against exactly these numbers. -/

section Guards

/-- A sample event, for the vectors below. -/
private def guardEvent₁ : Event := ⟨0, 12, .info, .app, "page opened".toList,
  "https://example.org/".toList⟩

/-- A second sample event. -/
private def guardEvent₂ : Event := ⟨1, 40, .warn, .probe, "the relay did not answer".toList,
  "timeout".toList⟩

/-- A sample run. -/
private def guardLog : Log := ⟨100, [guardEvent₁, guardEvent₂], 0⟩

/-- The sample run, shared. -/
private def guardReport : Report :=
  shareReport [] .noRoom "swordfish".toList "https://relay.example.org".toList guardLog

-- the room never travels: only its eight-character handle does
#guard guardReport.room = "5799c0f1".toList
#guard guardReport.room ≠ "swordfish".toList
#guard (logText guardReport).length = 255
#guard logText guardReport =
  ("6b7a64696167:02:3537393963306631:68747470733a2f2f72656c61792e6578616d706c652e6f7267\n" ++
   "6b7a6c6f67::0c:01:09:70616765206f70656e6564:68747470733a2f2f6578616d706c652e6f72672f\n" ++
   "6b7a6c6f67:01:28:02:02:7468652072656c617920646964206e6f7420616e73776572:74696d656f7574").toList
-- the address of the posted run
#guard (logPaste "run_1".toList "1700000000".toList guardReport).witness =
  "8b0d60a6d87089066612b9b45273c16b078fb92940fd3c78dbdee66be14716e5".toList
-- three tweets carry the whole run
#guard (chatParts 100 guardReport).length = 3
#guard logTitle = "the run so far".toList

end Guards

end Kant.ShareLog
