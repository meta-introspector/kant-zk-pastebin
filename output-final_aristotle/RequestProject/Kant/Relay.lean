/-
# The rendezvous relay: a room, a mailbox, and a chat that nobody can forge

Two clients that have exchanged an invitation (`Kant.Rendezvous`) still
need somewhere to leave the first message.  That somewhere is a *relay*:
a dumb append-only mailbox, one log per room, that anybody can run — a
Cloudflare Worker, a Node process on a Linux box, or a peer already in
the room.

The relay is deliberately untrusted.  It never learns the secret behind a
room name (only its digest), and every line it hands out is checked by
the client that reads it: a chat message carries a witness over its own
fields, so a relay that edits, injects or replays a line is caught.

Proved here:

* `parseMsg_printMsg` — a chat message survives the wire;
* `parseMsg_eq_none_of_mismatch`, `relay_cannot_forge` — a line whose
  witness does not match its content is dropped, not displayed;
* `lines_post`, `post_prefix` — the relay is append-only: posting adds one
  line to one room and touches nothing else;
* `fetch_since` — polling with the cursor you were last given returns
  exactly what has been posted since, no gaps and no repeats;
* `poll_lossless` — polling in several steps sees the same lines as
  polling once;
* `mem_receive_iff`, `receive_perm` — what a client holds is exactly the
  well-formed messages it was handed, in any order;
* `transcript_perm` — the rendered transcript is a function of that set,
  so **two clients that received the same messages display the same
  chat**, whichever relay, cursor schedule or peer route they used;
* `clients_agree` — the capstone: same room, same lines, same chat;
* `discover_via_relay` — announcements posted to a room are discovered by
  everyone else polling that room.
-/
import Mathlib
import RequestProject.Kant.Bytes
import RequestProject.Kant.Text
import RequestProject.Kant.Clipboard
import RequestProject.Kant.Rendezvous

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.Relay

open Kant Kant.Bytes Kant.Text Kant.Clipboard Kant.Rendezvous

/-! ## Chat messages -/

/-- A line of chat: who said it, in which room, at which position in
their own numbering, and what they said. -/
structure Msg where
  /-- The room, i.e. the digest of the invitation secret. -/
  room : List Char
  /-- The peer that wrote it. -/
  sender : List Char
  /-- The writer's own counter. -/
  seq : Nat
  /-- The message body. -/
  body : Blob
deriving DecidableEq, Repr

/-- A message is transmissible when its text fields are ASCII. -/
structure Msg.Wire (m : Msg) : Prop where
  /-- The room name is ASCII (it is hex, in practice). -/
  room : IsAscii m.room
  /-- The sender identifier is ASCII. -/
  sender : IsAscii m.sender

/-- The bytes a message commits to. -/
def Msg.core (m : Msg) : Blob :=
  asciiBytes m.room ++ 0 :: asciiBytes m.sender ++ 0 :: natToBytesBE m.seq ++ 0 :: m.body

/-- The self-certifying witness of a message. -/
def Msg.witness (m : Msg) : List Char := Kant.Bytes.witness m.core

@[simp] theorem Msg.witness_length (m : Msg) : m.witness.length = 64 :=
  Kant.Bytes.witness_length _

/-- Tag of a chat line on the wire. -/
def tagChat : Blob := asciiBytes "kzchat".toList

/-- A message as an envelope, witness included. -/
def ofMsg (m : Msg) : Envelope :=
  ⟨tagChat,
    [asciiBytes m.room, asciiBytes m.sender, natToBytesBE m.seq, m.body, asciiBytes m.witness]⟩

/-- Read a message back, **rejecting** anything whose witness does not
match the content that arrived. -/
def toMsg (e : Envelope) : Option Msg :=
  if e.tag ≠ tagChat then none
  else
    match e.fields with
    | [r, s, q, b, w] =>
        let m : Msg := ⟨asciiChars r, asciiChars s, bytesBEToNat q, b⟩
        if m.witness = asciiChars w then some m else none
    | _ => none

/-- A message as one line of text: what is posted to a relay, sent over a
data channel, or pasted into any other chat. -/
def printMsg (m : Msg) : List Char := (ofMsg m).encode

/-- Read a line of text as a message. -/
def parseMsg (s : List Char) : Option Msg := (Envelope.decode s).bind toMsg

/-- **A chat message survives the wire.** -/
theorem parseMsg_printMsg {m : Msg} (h : m.Wire) : parseMsg (printMsg m) = some m := by
  unfold parseMsg printMsg
  rw [Envelope.decode_encode]
  have hw : asciiChars (asciiBytes m.witness) = m.witness :=
    asciiChars_asciiBytes (isAscii_hexEncode _)
  cases m with
  | mk r s q b =>
      simp only [Option.bind_some, toMsg, ofMsg, ne_eq, not_true_eq_false, if_false,
        asciiChars_asciiBytes h.room, asciiChars_asciiBytes h.sender,
        bytesBEToNat_natToBytesBE] at hw ⊢
      rw [hw, if_pos rfl]

/-- Chat lines are plain ASCII. -/
theorem isAscii_printMsg (m : Msg) : IsAscii (printMsg m) := Envelope.isAscii_encode _

/-- **A tampered line is refused.**  If the witness travelling with a
line is not the witness of the content that arrived, the line does not
become a message. -/
theorem parseMsg_eq_none_of_mismatch {r s q b w : Blob}
    (h : (Msg.mk (asciiChars r) (asciiChars s) (bytesBEToNat q) b).witness ≠ asciiChars w) :
    toMsg ⟨tagChat, [r, s, q, b, w]⟩ = none := by
  simp only [toMsg, ne_eq, not_true_eq_false, if_false]
  exact if_neg h

/-- A parsed message carries exactly the witness that was transmitted. -/
theorem parseMsg_witness_field {r s q b w : Blob} {m : Msg}
    (h : toMsg ⟨tagChat, [r, s, q, b, w]⟩ = some m) : m.witness = asciiChars w := by
  simp only [toMsg, ne_eq, not_true_eq_false, if_false] at h
  by_cases hw : (Msg.mk (asciiChars r) (asciiChars s) (bytesBEToNat q) b).witness = asciiChars w
  · rw [if_pos hw] at h
    simp only [Option.some.injEq] at h
    rw [← h]
    exact hw
  · rw [if_neg hw] at h
    exact absurd h (by simp)

/-- Printing a message is injective on transmissible messages: distinct
chat lines never render to the same text. -/
theorem printMsg_injective {a b : Msg} (ha : a.Wire) (hb : b.Wire) (h : printMsg a = printMsg b) :
    a = b := by
  have h₁ := parseMsg_printMsg ha
  have h₂ := parseMsg_printMsg hb
  rw [h, h₂] at h₁
  exact (Option.some.injEq _ _ ▸ h₁).symm

/-! ## The relay: one append-only log per room -/

/-- A relay: rooms, each holding the lines posted to it in arrival order.
Nothing else is stored; the relay never parses what it carries. -/
structure Server where
  /-- The mailboxes, keyed by room. -/
  rooms : List (List Char × List (List Char))
deriving Repr

namespace Server

/-- A relay with no rooms. -/
def empty : Server := ⟨[]⟩

/-- The log of a room. -/
def lines (sv : Server) (room : List Char) : List (List Char) :=
  match sv.rooms.find? (fun e => e.1 == room) with
  | some e => e.2
  | none => []

/-- Replace the log of a room. -/
def setLines (sv : Server) (room : List Char) (ls : List (List Char)) : Server :=
  ⟨(room, ls) :: sv.rooms.filter (fun e => e.1 != room)⟩

/-- Append a line to a room. -/
def post (sv : Server) (room : List Char) (line : List Char) : Server :=
  sv.setLines room (sv.lines room ++ [line])

/-- Everything a room holds from `cursor` onwards, plus the new cursor. -/
def fetch (sv : Server) (room : List Char) (cursor : Nat) : List (List Char) × Nat :=
  ((sv.lines room).drop cursor, (sv.lines room).length)

@[simp] theorem lines_setLines_self (sv : Server) (room : List Char) (ls : List (List Char)) :
    (sv.setLines room ls).lines room = ls := by
  simp [setLines, lines]

@[simp] theorem lines_setLines_other {room room' : List Char} (h : room' ≠ room)
    (sv : Server) (ls : List (List Char)) :
    (sv.setLines room ls).lines room' = sv.lines room' := by
  have hne : (room == room') = false := by simp [Ne.symm h]
  have key : ∀ rs : List (List Char × List (List Char)),
      (rs.filter (fun e => e.1 != room)).find? (fun e => e.1 == room')
        = rs.find? (fun e => e.1 == room') := by
    intro rs
    induction rs with
    | nil => rfl
    | cons e es ih =>
        by_cases he : e.1 = room
        · have h1 : (e.1 != room) = false := by simp [he]
          have h2 : (e.1 == room') = false := by simp [he, Ne.symm h]
          simp [h1, h2, ih]
        · have h1 : (e.1 != room) = true := by simp [he]
          simp [h1, List.find?_cons, ih]
  simp only [setLines, lines, List.find?_cons, hne, key]

/-- **The relay is an append-only log.**  Posting adds exactly one line
to exactly one room. -/
@[simp] theorem lines_post (sv : Server) (room line : List Char) :
    (sv.post room line).lines room = sv.lines room ++ [line] := by
  simp [post]

/-- Posting to one room does not disturb another. -/
theorem lines_post_other {room room' : List Char} (h : room' ≠ room) (sv : Server)
    (line : List Char) : (sv.post room line).lines room' = sv.lines room' := by
  simp [post, lines_setLines_other h]

/-- Nothing already posted is ever removed or reordered. -/
theorem post_prefix (sv : Server) (room line : List Char) :
    sv.lines room <+: (sv.post room line).lines room := by
  simp [lines_post]

/-- The empty relay serves nothing. -/
@[simp] theorem lines_empty (room : List Char) : empty.lines room = [] := rfl

/-- **Polling with the cursor you were given returns exactly what has
been posted since** — the new line, once, and nothing else. -/
theorem fetch_since (sv : Server) (room line : List Char) :
    ((sv.post room line).fetch room (sv.lines room).length) =
      ([line], (sv.lines room).length + 1) := by
  simp [fetch, lines_post]

/-- Polling from the start returns the whole room. -/
theorem fetch_zero (sv : Server) (room : List Char) :
    (sv.fetch room 0).1 = sv.lines room := by simp [fetch]

/-- The cursor a poll returns is the current length of the log. -/
theorem fetch_cursor (sv : Server) (room : List Char) (c : Nat) :
    (sv.fetch room c).2 = (sv.lines room).length := rfl

/-- **Polling in stages loses nothing.**  Reading up to cursor `d` and
then from `d` onwards yields exactly what one read from `c` would. -/
theorem poll_lossless (sv : Server) (room : List Char) {c d : Nat} (h : c ≤ d) :
    ((sv.lines room).take d).drop c ++ (sv.fetch room d).1 = (sv.fetch room c).1 := by
  simp only [fetch]
  have h1 : ((sv.lines room).take d).drop c = ((sv.lines room).drop c).take (d - c) := by
    rw [List.drop_take]
  have h2 : (sv.lines room).drop d = ((sv.lines room).drop c).drop (d - c) := by
    rw [List.drop_drop]
    congr 1
    omega
  rw [h1, h2, List.take_append_drop]

end Server

/-! ## What a client keeps

A client folds the lines it is handed — from a relay poll, a peer data
channel, a QR scan, a pasted string — into a set of messages, dropping
anything that does not certify itself. -/

/-- Take one line from anywhere. -/
def accept (ms : List Msg) (line : List Char) : List Msg :=
  match parseMsg line with
  | some m => if m ∈ ms then ms else m :: ms
  | none => ms

/-- Take a batch of lines. -/
def receive (ms : List Msg) (ls : List (List Char)) : List Msg := ls.foldl accept ms

@[simp] theorem receive_nil (ms : List Msg) : receive ms [] = ms := rfl

@[simp] theorem receive_cons (ms : List Msg) (l : List Char) (ls : List (List Char)) :
    receive ms (l :: ls) = receive (accept ms l) ls := rfl

theorem mem_accept_iff {ms : List Msg} {l : List Char} {x : Msg} :
    x ∈ accept ms l ↔ (x ∈ ms ∨ parseMsg l = some x) := by
  unfold accept
  cases h : parseMsg l with
  | none => simp
  | some m =>
      by_cases hm : m ∈ ms
      · simp only [hm, if_true, Option.some.injEq]
        constructor
        · exact Or.inl
        · rintro (hx | rfl) <;> simp_all
      · simp [hm, or_comm, eq_comm]

/-- **A client holds exactly the well-formed messages it was handed.** -/
theorem mem_receive_iff {ms : List Msg} {ls : List (List Char)} {x : Msg} :
    x ∈ receive ms ls ↔ (x ∈ ms ∨ ∃ l ∈ ls, parseMsg l = some x) := by
  induction ls generalizing ms with
  | nil => simp
  | cons l ls ih =>
      rw [receive_cons, ih, mem_accept_iff]
      simp only [List.mem_cons]
      constructor
      · rintro ((hx | hx) | ⟨l', hl', hx⟩)
        · exact Or.inl hx
        · exact Or.inr ⟨l, Or.inl rfl, hx⟩
        · exact Or.inr ⟨l', Or.inr hl', hx⟩
      · rintro (hx | ⟨l', (rfl | hl'), hx⟩)
        · exact Or.inl (Or.inl hx)
        · exact Or.inl (Or.inr hx)
        · exact Or.inr ⟨l', hl', hx⟩

/-- **The order lines arrive in is irrelevant.** -/
theorem receive_perm {ms : List Msg} {ls ls' : List (List Char)} (h : ls.Perm ls') (x : Msg) :
    x ∈ receive ms ls ↔ x ∈ receive ms ls' := by
  simp only [mem_receive_iff]
  constructor <;> rintro (hx | ⟨l, hl, hx⟩)
  · exact Or.inl hx
  · exact Or.inr ⟨l, h.mem_iff.mp hl, hx⟩
  · exact Or.inl hx
  · exact Or.inr ⟨l, h.mem_iff.mpr hl, hx⟩

/-- **A forged line is dropped.**  Anything the relay makes up — or
edits — fails to parse and never reaches the transcript. -/
theorem relay_cannot_forge {ms : List Msg} {l : List Char} (h : parseMsg l = none) :
    accept ms l = ms := by simp [accept, h]

/-- A client never loses a message it already had. -/
theorem receive_preserves {ms : List Msg} {ls : List (List Char)} {x : Msg} (h : x ∈ ms) :
    x ∈ receive ms ls := mem_receive_iff.mpr (Or.inl h)

/-- Everything well formed that was handed over is kept. -/
theorem receive_delivers {ms : List Msg} {ls : List (List Char)} {l : List Char} {x : Msg}
    (hl : l ∈ ls) (hx : parseMsg l = some x) : x ∈ receive ms ls :=
  mem_receive_iff.mpr (Or.inr ⟨l, hl, hx⟩)

/-! ## Rendering the transcript

Messages are displayed in the writers' counter order, ties broken by the
text of the message itself, so the order is a function of the set of
messages and of nothing else — not of arrival order, not of the relay. -/

/-- The display order: by counter, then by the line itself. -/
def leMsg (a b : Msg) : Bool :=
  (a.seq < b.seq) || (a.seq == b.seq && decide (printMsg a ≤ printMsg b))

theorem leMsg_trans (a b c : Msg) (hab : leMsg a b = true) (hbc : leMsg b c = true) :
    leMsg a c = true := by
  simp only [leMsg, Bool.or_eq_true, Bool.and_eq_true, decide_eq_true_eq, beq_iff_eq] at *
  rcases hab with h₁ | ⟨h₁, h₁'⟩ <;> rcases hbc with h₂ | ⟨h₂, h₂'⟩
  · exact Or.inl (lt_trans h₁ h₂)
  · exact Or.inl (h₂ ▸ h₁)
  · exact Or.inl (h₁ ▸ h₂)
  · exact Or.inr ⟨h₁.trans h₂, le_trans h₁' h₂'⟩

theorem leMsg_total (a b : Msg) : (leMsg a b || leMsg b a) = true := by
  simp only [leMsg, Bool.or_eq_true, Bool.and_eq_true, decide_eq_true_eq, beq_iff_eq]
  rcases lt_trichotomy a.seq b.seq with h | h | h
  · exact Or.inl (Or.inl h)
  · rcases le_total (printMsg a) (printMsg b) with hle | hle
    · exact Or.inl (Or.inr ⟨h, hle⟩)
    · exact Or.inr (Or.inr ⟨h.symm, hle⟩)
  · exact Or.inr (Or.inl h)

theorem leMsg_antisymm {a b : Msg} (ha : a.Wire) (hb : b.Wire)
    (hab : leMsg a b = true) (hba : leMsg b a = true) : a = b := by
  simp only [leMsg, Bool.or_eq_true, Bool.and_eq_true, decide_eq_true_eq, beq_iff_eq] at hab hba
  rcases hab with h₁ | ⟨_, h₁⟩ <;> rcases hba with h₂ | ⟨_, h₂⟩
  · exact absurd h₁ (by omega)
  · exact absurd h₁ (by omega)
  · exact absurd h₂ (by omega)
  · exact printMsg_injective ha hb (le_antisymm h₁ h₂)

/-- The transcript a client displays: its messages, deduplicated and put
in display order. -/
def transcript (ms : List Msg) : List Msg := (ms.dedup).mergeSort leMsg

theorem mem_transcript {ms : List Msg} {x : Msg} : x ∈ transcript ms ↔ x ∈ ms := by
  unfold transcript
  rw [(List.mergeSort_perm _ _).mem_iff, List.mem_dedup]

theorem transcript_sorted (ms : List Msg) :
    List.Pairwise (fun a b => leMsg a b = true) (transcript ms) :=
  List.pairwise_mergeSort leMsg_trans leMsg_total _

/-- **Two clients that hold the same messages display the same chat.**
Arrival order, cursor schedule, relay choice and transport are all
invisible in the result. -/
theorem transcript_perm {ms₁ ms₂ : List Msg} (hw : ∀ m ∈ ms₁, m.Wire) (h : ms₁.Perm ms₂) :
    transcript ms₁ = transcript ms₂ := by
  have hperm : (transcript ms₁).Perm (transcript ms₂) := by
    unfold transcript
    exact ((List.mergeSort_perm _ _).trans (h.dedup)).trans (List.mergeSort_perm _ _).symm
  refine List.Perm.eq_of_pairwise ?_ (transcript_sorted ms₁) (transcript_sorted ms₂) hperm
  intro a b ha hb hab hba
  exact leMsg_antisymm (hw a (mem_transcript.mp ha))
    (hw b (h.mem_iff.mpr (mem_transcript.mp hb))) hab hba

/-- A client's message set never contains duplicates. -/
theorem receive_nodup {ms : List Msg} (hms : ms.Nodup) (ls : List (List Char)) :
    (receive ms ls).Nodup := by
  induction ls generalizing ms with
  | nil => exact hms
  | cons l ls ih =>
      refine ih ?_
      unfold accept
      cases hp : parseMsg l with
      | none => exact hms
      | some m =>
          by_cases hm : m ∈ ms
          · simpa [hm] using hms
          · simpa [hm] using List.nodup_cons.mpr ⟨hm, hms⟩

/-- **The capstone.**  Two clients in the same room that were handed the
same lines — in any order, by any relay or peer — end up displaying
exactly the same transcript. -/
theorem clients_agree {ls ls' : List (List Char)} (h : ls.Perm ls')
    (hw : ∀ l ∈ ls, ∀ m, parseMsg l = some m → m.Wire) :
    transcript (receive [] ls) = transcript (receive [] ls') := by
  have hperm : (receive [] ls).Perm (receive [] ls') :=
    (List.perm_ext_iff_of_nodup (receive_nodup List.nodup_nil ls)
      (receive_nodup List.nodup_nil ls')).mpr (fun x => receive_perm h x)
  refine transcript_perm ?_ hperm
  intro m hm
  rcases mem_receive_iff.mp hm with hx | ⟨l, hl, hx⟩
  · simp at hx
  · exact hw l hl m hx

/-! ## Discovery through the relay

The same mailbox carries peer announcements: a client posts its own
`kzpeer` line into the room, polls, and folds whatever announcements come
back into its roster. -/

/-- Fold announcement lines from a poll into a roster. -/
def acceptPeers (r : Roster) (ls : List (List Char)) : Roster :=
  Roster.merge r (ls.filterMap parseAnnounce)

/-- Peers heard from the relay are recorded; peers already known are kept. -/
theorem mem_acceptPeers_iff {r : Roster} {ls : List (List Char)} {x : Announce} :
    x ∈ acceptPeers r ls ↔ (x ∈ r ∨ ∃ l ∈ ls, parseAnnounce l = some x) := by
  rw [acceptPeers, Roster.mem_merge_iff, List.mem_filterMap]

/-- **Two strangers find each other through the relay.**  A client that
posts its announcement into a room is discovered by everybody who polls
that room afterwards. -/
theorem discover_via_relay (sv : Server) (room : List Char) {a : Announce} (h : a.Wire)
    (r : Roster) :
    Roster.knows (acceptPeers r ((sv.post room (printAnnounce a)).fetch room 0).1) a.peer
      = true := by
  refine Roster.knows_iff.mpr ⟨a, ?_, rfl⟩
  refine mem_acceptPeers_iff.mpr (Or.inr ⟨printAnnounce a, ?_, parseAnnounce_printAnnounce h⟩)
  rw [Server.fetch_zero, Server.lines_post]
  exact List.mem_append_right _ (List.mem_singleton_self _)

end Kant.Relay
