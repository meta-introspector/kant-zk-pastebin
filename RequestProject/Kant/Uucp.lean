/-
# The static sneakernet: DMs, tweets and bang paths, with no relay at all

`Kant.Relay` gives a room a mailbox that somebody has to run.  This
module removes it.  A node keeps its own *spool* of self-certifying
messages (`Kant.Relay.Msg`) and hands it to other nodes the way UUCP
did: as a *mailbag* — one line of plain text that fits in a direct
message, a tweet, a QR code or the fragment of a URL.  You paste what
somebody sent you; you copy what you have and send it on.  Nothing in
this file mentions a server: the only moving part is the clipboard.

The consequences, all proved below:

* `openBag_packBag` — a bag copied into a DM and pasted out the other
  side is the very same list of messages;
* `bag_rejects_forgery`, `paste_bad` — a bag with one doctored line does
  not open at all, so a courier can drop mail but never invent it;
* `mem_sneakernet_iff` — **a node knows exactly what it knew plus what
  the codes it pasted carried**: no paste, no news.  This is the precise
  sense in which you are only as up to date as the last URL or QR code
  you pasted;
* `paste_perm`, `paste_idem`, `paste_monotone` — pastes commute, repeat
  harmlessly and never lose anything, so the mailbags may travel by any
  route in any order;
* `handoff`, `bag_canonical`, `exchange_agree` — one bag catches you up
  with the sender, nodes that know the same things emit the same code;
  two bags, one each way, and both sides display the same transcript;
* `uucp_path` — store and forward: a bag carried A → C → B delivers A's
  messages to B, and `uucp_route` iterates that over a whole bang path;
* `relay_keeps_current`, `stale_without_paste` — the one exception and
  its mirror: connected to a relay you are current without pasting
  anything; disconnected and pasting nothing, your view never changes;
* `sneakernet_matches_relay` — the capstone: what a node ends up
  displaying after pasting bags is *exactly* what a client of the relay
  in `Kant.Relay` would display after being handed the same messages.
  The relay is therefore redundant, not merely optional;
* `thread_*` — a bag too big for one tweet goes out as numbered parts,
  each of which fits, and which may be collected in any order;
* `Site.*` — the static server: a read-only map from path to text.
  Serving never changes it (`serve_static`), a visitor who pastes the
  published bag catches up with the publisher (`visitor_catches_up`),
  and a message written *after* publication is provably invisible until
  a fresher code is pasted (`snapshot_is_stale`).
-/
import Mathlib
import RequestProject.Kant.Bytes
import RequestProject.Kant.Text
import RequestProject.Kant.Clipboard
import RequestProject.Kant.Sneakernet
import RequestProject.Kant.Rendezvous
import RequestProject.Kant.Relay

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.Uucp

open Kant Kant.Bytes Kant.Text Kant.Clipboard Kant.Rendezvous Kant.Relay Kant.Sneakernet

/-! ## What you can paste into

The sneakernet uses the carriers everybody already has: a tweet, a
direct message, a QR code on a screen, the address bar, a profile
biography, the alt text of a picture.  Each has a hard character cap. -/

/-- A hand-carried text channel. -/
inductive Carrier
  | tweet | dm | qr | urlBar | bio | altText
deriving DecidableEq, Repr

/-- How many characters the carrier holds. -/
def Carrier.capacity : Carrier → Nat
  | .tweet => 280
  | .dm => 10000
  | .qr => 2953           -- QR version 40, byte mode
  | .urlBar => 2000
  | .bio => 160
  | .altText => 1000

theorem Carrier.capacity_pos (c : Carrier) : 0 < c.capacity := by cases c <;> decide

/-! ## The mailbag

A bag is an envelope whose fields are the printed chat lines of
`Kant.Relay`.  Those lines are ASCII and self-certifying, so they nest
inside the envelope with no further escaping and arrive either intact or
not at all. -/

/-- Tag of a mailbag. -/
def tagBag : Blob := asciiBytes "kzbag".toList

/-- A batch of messages as one envelope. -/
def ofBag (ms : List Msg) : Envelope :=
  ⟨tagBag, ms.map (fun m => asciiBytes (printMsg m))⟩

/-- Read the message fields of a bag, refusing the whole bag if any one
line fails to certify itself. -/
def readMsgs : List Blob → Option (List Msg)
  | [] => some []
  | f :: fs =>
      match parseMsg (asciiChars f), readMsgs fs with
      | some m, some ms => some (m :: ms)
      | _, _ => none

/-- Read a bag out of an envelope. -/
def toBag (e : Envelope) : Option (List Msg) :=
  if e.tag ≠ tagBag then none else readMsgs e.fields

/-- The text you paste into a DM or a tweet. -/
def packBag (ms : List Msg) : List Char := (ofBag ms).encode

/-- Read a pasted bag. -/
def openBag (s : List Char) : Option (List Msg) := (Envelope.decode s).bind toBag

theorem readMsgs_ofBag {ms : List Msg} (h : ∀ m ∈ ms, m.Wire) :
    readMsgs (ms.map (fun m => asciiBytes (printMsg m))) = some ms := by
  induction ms with
  | nil => rfl
  | cons m ms ih =>
      have hm : m.Wire := h m (by simp)
      have hrest : ∀ x ∈ ms, x.Wire := fun x hx => h x (by simp [hx])
      have hascii : asciiChars (asciiBytes (printMsg m)) = printMsg m :=
        asciiChars_asciiBytes (isAscii_printMsg m)
      simp only [List.map_cons, readMsgs, hascii, parseMsg_printMsg hm, ih hrest]

/-- **A mailbag survives a direct message.** -/
theorem openBag_packBag {ms : List Msg} (h : ∀ m ∈ ms, m.Wire) : openBag (packBag ms) = some ms := by
  unfold openBag packBag
  rw [Envelope.decode_encode]
  simp only [Option.bind_some, toBag, ofBag, ne_eq, not_true_eq_false, if_false,
    readMsgs_ofBag h]

/-- A bag is plain ASCII, so it travels through any text channel. -/
theorem isAscii_packBag (ms : List Msg) : IsAscii (packBag ms) := Envelope.isAscii_encode _

/-- One bad line spoils the bag: if any field fails to certify itself,
nothing is read. -/
theorem readMsgs_eq_none {fs : List Blob} (h : ∃ f ∈ fs, parseMsg (asciiChars f) = none) :
    readMsgs fs = none := by
  induction fs with
  | nil => simp at h
  | cons f fs ih =>
      rcases h with ⟨g, hg, hgn⟩
      rcases List.mem_cons.mp hg with rfl | hg'
      · simp [readMsgs, hgn]
      · have : readMsgs fs = none := ih ⟨g, hg', hgn⟩
        cases hf : parseMsg (asciiChars f) <;> simp [readMsgs, hf, this]

/-- **A courier cannot forge mail.**  A bag carrying a line whose witness
does not match its content is refused outright. -/
theorem bag_rejects_forgery {e : Envelope} (h : ∃ f ∈ e.fields, parseMsg (asciiChars f) = none) :
    toBag e = none := by
  unfold toBag
  split
  · rfl
  · exact readMsgs_eq_none h

/-! ## A bag as a link, and as a QR code -/

/-- A bag as the fragment of a URL you can paste in the address bar. -/
def bagUrl (base : List Char) (ms : List Msg) : List Char := shareUrl base (ofBag ms)

/-- Read a bag out of a pasted URL. -/
def readBagUrl (u : List Char) : Option (List Msg) := (parseShareUrl u).bind toBag

/-- **The whole state travels in a link.** -/
theorem readBagUrl_bagUrl {base : List Char} (hb : hash ∉ base) {ms : List Msg}
    (h : ∀ m ∈ ms, m.Wire) : readBagUrl (bagUrl base ms) = some ms := by
  unfold readBagUrl bagUrl
  rw [parseShareUrl_shareUrl hb]
  simp only [Option.bind_some, toBag, ofBag, ne_eq, not_true_eq_false, if_false,
    readMsgs_ofBag h]

/-- A small bag fits in one QR code. -/
theorem bag_fits_qr {ms : List Msg}
    (hsum : (((ofBag ms).fields).map List.length).sum ≤ 1450)
    (hn : ms.length ≤ 40) :
    (packBag ms).length ≤ Carrier.qr.capacity := by
  have h := Envelope.encode_length_le (ofBag ms)
  have htag : (ofBag ms).tag.length = 5 := rfl
  have hlen : ((ofBag ms).fields).length = ms.length := by simp [ofBag]
  have hpack : (packBag ms).length = (ofBag ms).encode.length := rfl
  rw [htag, hlen] at h
  simp only [Carrier.capacity, hpack]
  omega

/-! ## Bags too big for one tweet

A bag that does not fit in the carrier goes out as a numbered thread:
the sneakernet framing of `Kant.Sneakernet` cuts it into parts, each part
is a little envelope of its own, and the reader puts them back together
in whatever order they arrive. -/

/-- Tag of one part of a threaded bag. -/
def tagPart : Blob := asciiBytes "kzleg".toList

/-- A numbered part as an envelope. -/
def ofPart (f : Frame) : Envelope :=
  ⟨tagPart, [natToBytesBE f.seq, natToBytesBE f.total, f.payload]⟩

/-- Read a numbered part back. -/
def toPart (e : Envelope) : Option Frame :=
  if e.tag ≠ tagPart then none
  else
    match e.fields with
    | [s, t, p] => some ⟨bytesBEToNat s, bytesBEToNat t, p⟩
    | _ => none

@[simp] theorem toPart_ofPart (f : Frame) : toPart (ofPart f) = some f := by
  simp only [toPart, ofPart, ne_eq, not_true_eq_false, if_false, bytesBEToNat_natToBytesBE]

/-- Cut a text into numbered parts of at most `limit` bytes of payload. -/
def thread (limit : Nat) (s : List Char) : List (List Char) :=
  (frames limit (asciiBytes s)).map (fun f => (ofPart f).encode)

/-- Read the parts that were collected. -/
def readParts : List (List Char) → Option (List Frame)
  | [] => some []
  | t :: ts =>
      match (Envelope.decode t).bind toPart, readParts ts with
      | some f, some fs => some (f :: fs)
      | _, _ => none

/-- Put a threaded bag back together. -/
def readThread (ts : List (List Char)) : Option (List Char) :=
  (readParts ts).map (fun fs => asciiChars (reassemble fs))

theorem readParts_map (fs : List Frame) :
    readParts (fs.map (fun f => (ofPart f).encode)) = some fs := by
  induction fs with
  | nil => rfl
  | cons f fs ih =>
      simp only [List.map_cons, readParts, Envelope.decode_encode, Option.bind_some,
        toPart_ofPart, ih]

/-- **A threaded bag reads back as the text it was made from.** -/
theorem readThread_thread {limit : Nat} (hlim : 0 < limit) {s : List Char} (hs : IsAscii s) :
    readThread (thread limit s) = some s := by
  unfold readThread thread
  rw [readParts_map]
  simp only [Option.map_some]
  rw [reassemble_frames hlim, asciiChars_asciiBytes hs]

/-- **The parts may be posted and collected in any order.** -/
theorem readThread_perm {limit : Nat} (hlim : 0 < limit) {s : List Char} (hs : IsAscii s)
    {fs : List Frame} (hperm : (frames limit (asciiBytes s)).Perm fs) :
    readThread (fs.map (fun f => (ofPart f).encode)) = some s := by
  unfold readThread
  rw [readParts_map]
  simp only [Option.map_some]
  rw [reassemble_frames_perm hlim _ hperm, asciiChars_asciiBytes hs]

theorem natToBytesBE_length_le : ∀ {k n : Nat}, n < 256 ^ k → (natToBytesBE n).length ≤ k := by
  intro k
  induction k with
  | zero =>
      intro n hn
      simp only [pow_zero] at hn
      have : n = 0 := by omega
      simp [this, natToBytesBE]
  | succ k ih =>
      intro n hn
      rw [natToBytesBE]
      by_cases h : n = 0
      · simp [h]
      · have hdiv : n / 256 < 256 ^ k := by
          have : n < 256 ^ k * 256 := by rw [pow_succ] at hn; exact hn
          exact Nat.div_lt_of_lt_mul (by omega)
        have := ih hdiv
        simp only [List.length_append, List.length_cons, List.length_nil, if_neg h]
        omega

/-- Every frame of a threading carries the same total. -/
theorem frames_total_eq {limit : Nat} {data : Blob} {f : Frame} (hf : f ∈ frames limit data) :
    f.total = (chunk limit data).length := by
  simp only [frames, List.mem_map, List.mem_zipIdx_iff_getElem?] at hf
  obtain ⟨p, _, hp⟩ := hf
  exact (congrArg Frame.total hp.symm).trans rfl

/-- Sequence numbers are below the total. -/
theorem frames_seq_lt {limit : Nat} {data : Blob} {f : Frame} (hf : f ∈ frames limit data) :
    f.seq < (chunk limit data).length := by
  have h : f.seq ∈ (frames limit data).map Frame.seq := List.mem_map_of_mem hf
  rw [frames_seq] at h
  exact List.mem_range.mp h

/-- **A threaded bag fits in tweets.**  With a hundred bytes of payload
per part and fewer than sixteen million parts, every part of the thread
is inside the 280-character tweet limit. -/
theorem thread_fits_tweet {s : List Char}
    (hn : (chunk 100 (asciiBytes s)).length < 256 ^ 3) :
    ∀ t ∈ thread 100 s, t.length ≤ Carrier.tweet.capacity := by
  intro t ht
  simp only [thread, List.mem_map] at ht
  obtain ⟨f, hf, rfl⟩ := ht
  have hseq : (natToBytesBE f.seq).length ≤ 3 :=
    natToBytesBE_length_le (lt_trans (frames_seq_lt hf) hn)
  have htot : (natToBytesBE f.total).length ≤ 3 :=
    natToBytesBE_length_le (by rw [frames_total_eq hf]; exact hn)
  have hpay : f.payload.length ≤ 100 := frames_fit (asciiBytes s) f hf
  have h := Envelope.encode_length_le (ofPart f)
  have htag : (ofPart f).tag.length = 5 := rfl
  have hfields : (((ofPart f).fields).map List.length).sum
      = (natToBytesBE f.seq).length + ((natToBytesBE f.total).length + f.payload.length) := by
    simp [ofPart]
  have hcount : ((ofPart f).fields).length = 3 := rfl
  rw [htag, hfields, hcount] at h
  simp only [Carrier.capacity]
  omega

/-! ## A node: a spool and a clipboard

A node is a name, the messages it holds, and its own counter.  It has no
connection to anything.  It gains news only when somebody pastes a bag
into it, and it spreads news only by handing its own bag out. -/

/-- Add one message to a spool, unless it is already there. -/
def insertMsg (acc : List Msg) (m : Msg) : List Msg := if m ∈ acc then acc else m :: acc

theorem mem_insertMsg {acc : List Msg} {m x : Msg} :
    x ∈ insertMsg acc m ↔ (x ∈ acc ∨ x = m) := by
  unfold insertMsg
  by_cases hm : m ∈ acc
  · simp only [hm, if_true]
    constructor
    · exact Or.inl
    · rintro (h | rfl)
      · exact h
      · exact hm
  · simp [hm, or_comm]

theorem insertMsg_nodup {acc : List Msg} (h : acc.Nodup) (m : Msg) : (insertMsg acc m).Nodup := by
  unfold insertMsg
  by_cases hm : m ∈ acc
  · simpa [hm] using h
  · simpa [hm] using List.nodup_cons.mpr ⟨hm, h⟩

/-- Add messages to a spool, skipping the ones already there. -/
def absorb (spool : List Msg) (ms : List Msg) : List Msg := ms.foldl insertMsg spool

@[simp] theorem absorb_nil (spool : List Msg) : absorb spool [] = spool := rfl

@[simp] theorem absorb_cons (spool : List Msg) (m : Msg) (ms : List Msg) :
    absorb spool (m :: ms) = absorb (insertMsg spool m) ms := rfl

theorem mem_absorb_iff {spool ms : List Msg} {x : Msg} :
    x ∈ absorb spool ms ↔ (x ∈ spool ∨ x ∈ ms) := by
  induction ms generalizing spool with
  | nil => simp
  | cons m ms ih =>
      rw [absorb_cons, ih, mem_insertMsg]
      simp only [List.mem_cons]
      tauto

theorem absorb_nodup {spool : List Msg} (h : spool.Nodup) (ms : List Msg) :
    (absorb spool ms).Nodup := by
  induction ms generalizing spool with
  | nil => exact h
  | cons m ms ih => exact ih (insertMsg_nodup h m)

/-- A sneakernet node. -/
structure Node where
  /-- Who this node is. -/
  name : List Char
  /-- Everything it holds. -/
  spool : List Msg
  /-- The counter of its next own message. -/
  clock : Nat
deriving Repr

namespace Node

/-- A fresh node that knows nothing. -/
def blank (name : List Char) : Node := ⟨name, [], 0⟩

/-- Write a message of your own. -/
def write (n : Node) (room : List Char) (body : Blob) : Node :=
  ⟨n.name, absorb n.spool [⟨room, n.name, n.clock, body⟩], n.clock + 1⟩

/-- What the node displays: its messages, deduplicated and in display
order (`Kant.Relay.transcript`). -/
def view (n : Node) : List Msg := transcript n.spool

/-- The bag you hand out: everything you hold, as one line of text.  It
is built from the *displayed* order, so two nodes that know the same
messages hand out the very same code (`bag_canonical`). -/
def bag (n : Node) : List Char := packBag n.view

/-- Paste a code somebody sent you.  Anything that does not open, or does
not certify itself, leaves the node exactly as it was. -/
def paste (n : Node) (s : List Char) : Node :=
  match openBag s with
  | some ms => ⟨n.name, absorb n.spool ms, n.clock⟩
  | none => n

/-- Paste a whole pile of codes. -/
def sneakernet (n : Node) (ss : List (List Char)) : Node := ss.foldl paste n

@[simp] theorem name_paste (n : Node) (s : List Char) : (n.paste s).name = n.name := by
  unfold paste; split <;> rfl

@[simp] theorem clock_paste (n : Node) (s : List Char) : (n.paste s).clock = n.clock := by
  unfold paste; split <;> rfl

/-- **Nothing arrives unless you paste it.** -/
theorem paste_bad {n : Node} {s : List Char} (h : openBag s = none) : n.paste s = n := by
  simp [paste, h]

@[simp] theorem sneakernet_nil (n : Node) : n.sneakernet [] = n := rfl

@[simp] theorem sneakernet_cons (n : Node) (s : List Char) (ss : List (List Char)) :
    n.sneakernet (s :: ss) = (n.paste s).sneakernet ss := rfl

theorem mem_paste_iff {n : Node} {s : List Char} {x : Msg} :
    x ∈ (n.paste s).spool ↔ (x ∈ n.spool ∨ ∃ ms, openBag s = some ms ∧ x ∈ ms) := by
  unfold paste
  cases h : openBag s with
  | none => simp
  | some ms =>
      simp only [mem_absorb_iff, Option.some.injEq]
      constructor
      · rintro (hx | hx)
        · exact Or.inl hx
        · exact Or.inr ⟨ms, rfl, hx⟩
      · rintro (hx | ⟨ms', rfl, hx⟩)
        · exact Or.inl hx
        · exact Or.inr hx

/-- **You are exactly as up to date as the codes you pasted.**  A node's
spool is what it already held together with the contents of the bags it
was given — and nothing else. -/
theorem mem_sneakernet_iff {n : Node} {ss : List (List Char)} {x : Msg} :
    x ∈ (n.sneakernet ss).spool ↔
      (x ∈ n.spool ∨ ∃ s ∈ ss, ∃ ms, openBag s = some ms ∧ x ∈ ms) := by
  induction ss generalizing n with
  | nil => simp
  | cons s ss ih =>
      rw [sneakernet_cons, ih, mem_paste_iff]
      constructor
      · rintro ((hx | ⟨ms, hms, hx⟩) | ⟨t, ht, hx⟩)
        · exact Or.inl hx
        · exact Or.inr ⟨s, by simp, ms, hms, hx⟩
        · exact Or.inr ⟨t, by simp [ht], hx⟩
      · rintro (hx | ⟨t, ht, ms, hms, hx⟩)
        · exact Or.inl (Or.inl hx)
        · rcases List.mem_cons.mp ht with rfl | ht'
          · exact Or.inl (Or.inr ⟨ms, hms, hx⟩)
          · exact Or.inr ⟨t, ht', ms, hms, hx⟩

/-- Pasting never loses anything. -/
theorem paste_monotone {n : Node} {s : List Char} {x : Msg} (h : x ∈ n.spool) :
    x ∈ (n.paste s).spool := mem_paste_iff.mpr (Or.inl h)

/-- Everything a bag carries is kept. -/
theorem paste_delivers {n : Node} {s : List Char} {ms : List Msg} {x : Msg}
    (hs : openBag s = some ms) (hx : x ∈ ms) : x ∈ (n.paste s).spool :=
  mem_paste_iff.mpr (Or.inr ⟨ms, hs, hx⟩)

/-- **Pasting the same code twice tells you nothing new.** -/
theorem paste_idem (n : Node) (s : List Char) (x : Msg) :
    x ∈ ((n.paste s).paste s).spool ↔ x ∈ (n.paste s).spool := by
  rw [mem_paste_iff, mem_paste_iff (n := n)]
  constructor
  · rintro (hx | ⟨ms, hms, hx⟩)
    · exact hx
    · exact Or.inr ⟨ms, hms, hx⟩
  · exact Or.inl

/-- **The order codes are pasted in does not matter.** -/
theorem paste_perm {n : Node} {ss ts : List (List Char)} (h : ss.Perm ts) (x : Msg) :
    x ∈ (n.sneakernet ss).spool ↔ x ∈ (n.sneakernet ts).spool := by
  simp only [mem_sneakernet_iff]
  constructor <;> rintro (hx | ⟨s, hs, hrest⟩)
  · exact Or.inl hx
  · exact Or.inr ⟨s, h.mem_iff.mp hs, hrest⟩
  · exact Or.inl hx
  · exact Or.inr ⟨s, h.mem_iff.mpr hs, hrest⟩

/-- A node's spool never contains the same message twice. -/
theorem paste_nodup {n : Node} (h : n.spool.Nodup) (s : List Char) : (n.paste s).spool.Nodup := by
  unfold paste
  cases hs : openBag s with
  | none => exact h
  | some ms => exact absorb_nodup h ms

theorem sneakernet_nodup {n : Node} (h : n.spool.Nodup) (ss : List (List Char)) :
    (n.sneakernet ss).spool.Nodup := by
  induction ss generalizing n with
  | nil => exact h
  | cons s ss ih => exact ih (paste_nodup h s)

theorem blank_nodup (name : List Char) : (blank name).spool.Nodup := List.nodup_nil

/-- Every message a node holds is transmissible. -/
def Wired (n : Node) : Prop := ∀ m ∈ n.spool, m.Wire

theorem paste_wired {n : Node} (h : Wired n) {s : List Char}
    (hb : ∀ ms, openBag s = some ms → ∀ m ∈ ms, m.Wire) : Wired (n.paste s) := by
  intro m hm
  rcases mem_paste_iff.mp hm with hx | ⟨ms, hms, hx⟩
  · exact h m hx
  · exact hb ms hms m hx

end Node

/-! ## Handing bags around

The whole protocol: copy your bag, send it by whatever means, and the
other side pastes it. -/

/-- Everything a node displays is transmissible. -/
theorem wired_view {n : Node} (h : Node.Wired n) : ∀ m ∈ n.view, m.Wire :=
  fun m hm => h m (mem_transcript.mp hm)

/-- A node's own bag always opens, and opens as everything it holds. -/
theorem openBag_bag {n : Node} (h : Node.Wired n) : openBag n.bag = some n.view :=
  openBag_packBag (wired_view h)

/-- **One bag catches you up with the sender.**  Everything the sender
holds, the receiver holds after pasting the sender's bag. -/
theorem handoff {a b : Node} (ha : Node.Wired a) {x : Msg} (hx : x ∈ a.spool) :
    x ∈ (b.paste a.bag).spool :=
  Node.paste_delivers (openBag_bag ha) (mem_transcript.mpr hx)

/-- **The same knowledge produces the same code.**  Two nodes that hold
the same messages hand out identical bags, whatever order they collected
them in — so a code can be deduplicated, pinned or cached by its text. -/
theorem bag_canonical {a b : Node} (ha : Node.Wired a) (hna : a.spool.Nodup)
    (hnb : b.spool.Nodup) (h : ∀ x, x ∈ a.spool ↔ x ∈ b.spool) : a.bag = b.bag := by
  have hperm : a.spool.Perm b.spool := (List.perm_ext_iff_of_nodup hna hnb).mpr h
  unfold Node.bag Node.view
  rw [transcript_perm ha hperm]

/-- Being at least as up to date as somebody else. -/
def Fresher (a b : Node) : Prop := ∀ x ∈ b.spool, x ∈ a.spool

theorem fresher_refl (a : Node) : Fresher a a := fun _ hx => hx

theorem fresher_trans {a b c : Node} (hab : Fresher a b) (hbc : Fresher b c) : Fresher a c :=
  fun x hx => hab x (hbc x hx)

/-- Pasting anything only moves you forward. -/
theorem fresher_paste (n : Node) (s : List Char) : Fresher (n.paste s) n :=
  fun _ hx => Node.paste_monotone hx

/-- After the handoff the receiver is at least as fresh as the sender. -/
theorem fresher_handoff {a b : Node} (ha : Node.Wired a) : Fresher (b.paste a.bag) a :=
  fun _ hx => handoff ha hx

/-- Two nodes swap bags: each pastes the other's. -/
def exchange (a b : Node) : Node × Node := (a.paste b.bag, b.paste a.bag)

theorem exchange_mem {a b : Node} (ha : Node.Wired a) (hb : Node.Wired b) (x : Msg) :
    x ∈ (exchange a b).1.spool ↔ x ∈ (exchange a b).2.spool := by
  constructor
  · intro hx
    rcases Node.mem_paste_iff.mp hx with h | ⟨ms, hms, h⟩
    · exact handoff ha h
    · rw [openBag_bag hb, Option.some.injEq] at hms
      have hv : x ∈ b.view := by rw [hms]; exact h
      exact Node.paste_monotone (mem_transcript.mp hv)
  · intro hx
    rcases Node.mem_paste_iff.mp hx with h | ⟨ms, hms, h⟩
    · exact handoff hb h
    · rw [openBag_bag ha, Option.some.injEq] at hms
      have hv : x ∈ a.view := by rw [hms]; exact h
      exact Node.paste_monotone (mem_transcript.mp hv)

/-- **Two bags, one each way, and both sides show the same thing.**  No
relay, no server, no network: just two pasted codes. -/
theorem exchange_agree {a b : Node} (ha : Node.Wired a) (hb : Node.Wired b)
    (hna : a.spool.Nodup) (hnb : b.spool.Nodup) :
    (exchange a b).1.view = (exchange a b).2.view := by
  have hperm : (exchange a b).1.spool.Perm (exchange a b).2.spool :=
    (List.perm_ext_iff_of_nodup (Node.paste_nodup hna _) (Node.paste_nodup hnb _)).mpr
      (exchange_mem ha hb)
  refine transcript_perm ?_ hperm
  intro m hm
  rcases Node.mem_paste_iff.mp hm with h | ⟨ms, hms, h⟩
  · exact ha m h
  · rw [openBag_bag hb, Option.some.injEq] at hms
    have hv : m ∈ b.view := by rw [hms]; exact h
    exact hb m (mem_transcript.mp hv)

/-! ## Store and forward: the bang path

Nobody has to meet anybody.  A bag left with a courier who later hands
on their own bag delivers the mail just the same — that is all a UUCP
bang path `a!c!b` ever was. -/

/-- **A → C → B delivers.** -/
theorem uucp_path {a b c : Node} (ha : Node.Wired a)
    (hc : ∀ ms, openBag a.bag = some ms → ∀ m ∈ ms, m.Wire) (hcw : Node.Wired c)
    {x : Msg} (hx : x ∈ a.spool) :
    x ∈ (b.paste (c.paste a.bag).bag).spool :=
  handoff (Node.paste_wired hcw hc) (handoff ha hx)

/-- Carrying a bag along a whole path of couriers. -/
def route (start : Node) : List Node → Node
  | [] => start
  | hop :: hops => route (hop.paste start.bag) hops

/-- Freshness is preserved along a route: the last courier on the path
holds everything the originator held. -/
theorem uucp_route {start : Node} (hs : Node.Wired start)
    (hops : List Node) (hw : ∀ n ∈ hops, Node.Wired n) :
    Fresher (route start hops) start := by
  induction hops generalizing start with
  | nil => exact fresher_refl start
  | cons hop hops ih =>
      have hhop : Node.Wired hop := hw hop (by simp)
      have hrest : ∀ n ∈ hops, Node.Wired n := fun n hn => hw n (by simp [hn])
      have hnext : Node.Wired (hop.paste start.bag) := by
        refine Node.paste_wired hhop ?_
        intro ms hms m hm
        rw [openBag_bag hs, Option.some.injEq] at hms
        have hv : m ∈ start.view := by rw [hms]; exact hm
        exact hs m (mem_transcript.mp hv)
      exact fresher_trans (ih hnext hrest) (fresher_handoff hs)

/-! ## The one exception: a live relay

Everything above is what happens when nobody is connected.  If a node
*is* connected — to the relay of `Kant.Relay`, to a peer data channel, to
anything that hands it lines — then it takes those lines the same way it
takes a pasted bag, and it is current without anybody moving a code.
That is the whole of the difference between the two modes. -/

namespace Node

/-- Take lines from a live connection: a relay poll, a data channel, a
local bus.  Anything that does not certify itself is dropped. -/
def ingestLines (n : Node) (ls : List (List Char)) : Node :=
  ⟨n.name, absorb n.spool (ls.filterMap parseMsg), n.clock⟩

theorem mem_ingestLines_iff {n : Node} {ls : List (List Char)} {x : Msg} :
    x ∈ (n.ingestLines ls).spool ↔ (x ∈ n.spool ∨ ∃ l ∈ ls, parseMsg l = some x) := by
  simp only [ingestLines, mem_absorb_iff, List.mem_filterMap]

end Node

/-- **Connected, you are current.**  A node that polls a relay room from
the start holds every message the room carries, with nothing pasted. -/
theorem relay_keeps_current (sv : Server) (room : List Char) (n : Node) {m : Msg} (hm : m.Wire)
    (h : printMsg m ∈ sv.lines room) :
    m ∈ (n.ingestLines (sv.fetch room 0).1).spool := by
  refine Node.mem_ingestLines_iff.mpr (Or.inr ⟨printMsg m, ?_, parseMsg_printMsg hm⟩)
  rwa [Server.fetch_zero]

/-- **Disconnected, you are not.**  With nothing pasted and nothing
polled, a node's view is exactly what it was: the sneakernet is the only
way news travels, and it travels only when a human moves a code. -/
theorem stale_without_paste (n : Node) : (n.sneakernet []).view = n.view := rfl

/-! ## The relay is redundant

The relay of `Kant.Relay` folds the lines it hands out into a client's
message set with `Relay.receive`, and displays `Relay.transcript`.  A
sneakernet node folds pasted bags with `absorb` and displays the same
`transcript`.  The two agree: whatever a relay could have told you, a
pasted bag tells you just as well. -/

theorem mem_receive_printMsg {ms : List Msg} (h : ∀ m ∈ ms, m.Wire) (x : Msg) :
    x ∈ receive [] (ms.map printMsg) ↔ x ∈ ms := by
  rw [mem_receive_iff]
  constructor
  · rintro (hx | ⟨l, hl, hx⟩)
    · simp at hx
    · simp only [List.mem_map] at hl
      obtain ⟨m, hm, rfl⟩ := hl
      rw [parseMsg_printMsg (h m hm), Option.some.injEq] at hx
      exact hx ▸ hm
  · intro hx
    exact Or.inr ⟨printMsg x, List.mem_map_of_mem hx, parseMsg_printMsg (h x hx)⟩

/-- **A pasted bag is worth a relay.**  A node that starts empty and
pastes a bag displays exactly what a relay client displays after being
handed the same messages as lines. -/
theorem sneakernet_matches_relay {name : List Char} {ms : List Msg} (h : ∀ m ∈ ms, m.Wire) :
    ((Node.blank name).paste (packBag ms)).view = transcript (receive [] (ms.map printMsg)) := by
  have hspool : ((Node.blank name).paste (packBag ms)).spool = absorb [] ms := by
    simp [Node.paste, Node.blank, openBag_packBag h]
  have hnd₁ : (absorb [] ms).Nodup := absorb_nodup List.nodup_nil ms
  have hnd₂ : (receive [] (ms.map printMsg)).Nodup := receive_nodup List.nodup_nil _
  have hperm : (absorb [] ms).Perm (receive [] (ms.map printMsg)) := by
    refine (List.perm_ext_iff_of_nodup hnd₁ hnd₂).mpr ?_
    intro x
    rw [mem_absorb_iff, mem_receive_printMsg h]
    simp
  have hwire : ∀ m ∈ absorb ([] : List Msg) ms, m.Wire := by
    intro m hm
    rcases mem_absorb_iff.mp hm with hx | hx
    · simp at hx
    · exact h m hx
  unfold Node.view
  rw [hspool]
  exact transcript_perm hwire hperm

/-! ## The static server

There is still something worth calling a server, but it does nothing: a
map from path to text, served read-only.  Any object store, any pages
host, any pinned directory will do — and so will a file on a USB stick.
The only dynamic behaviour in the whole system is a human pasting a
fresher code. -/

/-- A static site: paths and the text served at them. -/
structure Site where
  /-- The published files. -/
  files : List (List Char × List Char)
deriving Repr

namespace Site

/-- A site with nothing on it. -/
def empty : Site := ⟨[]⟩

/-- What is served at a path. -/
def get (s : Site) (path : List Char) : Option (List Char) :=
  match s.files.find? (fun e => e.1 == path) with
  | some e => some e.2
  | none => none

/-- Publish text at a path. -/
def put (s : Site) (path body : List Char) : Site :=
  ⟨(path, body) :: s.files.filter (fun e => e.1 != path)⟩

/-- Serving a request: the site hands back the file and is unchanged. -/
def serve (s : Site) (path : List Char) : Site × Option (List Char) := (s, s.get path)

/-- **The server is static.**  Serving a request changes nothing: there
is no session, no queue and no state to lose. -/
@[simp] theorem serve_static (s : Site) (path : List Char) : (s.serve path).1 = s := rfl

@[simp] theorem serve_get (s : Site) (path : List Char) : (s.serve path).2 = s.get path := rfl

@[simp] theorem get_put_self (s : Site) (path body : List Char) :
    (s.put path body).get path = some body := by
  simp [put, get]

@[simp] theorem get_put_other {path path' : List Char} (h : path' ≠ path) (s : Site)
    (body : List Char) : (s.put path body).get path' = s.get path' := by
  have hne : (path == path') = false := by simp [Ne.symm h]
  have key : ∀ fs : List (List Char × List Char),
      (fs.filter (fun e => e.1 != path)).find? (fun e => e.1 == path')
        = fs.find? (fun e => e.1 == path') := by
    intro fs
    induction fs with
    | nil => rfl
    | cons e es ih =>
        by_cases he : e.1 = path
        · have h1 : (e.1 != path) = false := by simp [he]
          have h2 : (e.1 == path') = false := by simp [he, Ne.symm h]
          simp [h1, h2, ih]
        · have h1 : (e.1 != path) = true := by simp [he]
          simp [h1, List.find?_cons, ih]
  simp only [put, get, List.find?_cons, hne, key]

/-- Publishing a node's bag at a path. -/
def publish (s : Site) (path : List Char) (n : Node) : Site := s.put path n.bag

/-- What a visitor does: fetch the page and paste whatever it holds. -/
def visit (s : Site) (path : List Char) (v : Node) : Node :=
  match s.get path with
  | some body => v.paste body
  | none => v

/-- **A visitor catches up with the publisher**, with no server logic in
between: the page is a file, and the file is a bag. -/
theorem visitor_catches_up {s : Site} {path : List Char} {a v : Node} (ha : Node.Wired a)
    {x : Msg} (hx : x ∈ a.spool) :
    x ∈ ((s.publish path a).visit path v).spool := by
  unfold visit publish
  rw [get_put_self]
  exact handoff ha hx

/-- Publishing at one path does not disturb another. -/
theorem publish_other {path path' : List Char} (h : path' ≠ path) (s : Site) (n : Node) :
    (s.publish path n).get path' = s.get path' := get_put_other h s n.bag

/-- **A snapshot is a snapshot.**  A message the publisher writes *after*
publishing is not in the published page, so a visitor who pastes that
page does not learn it.  Only a fresher code — or a live connection —
can carry it. -/
theorem snapshot_is_stale {s : Site} {path : List Char} {a v : Node} {room : List Char}
    {body : Blob} (ha : Node.Wired a)
    (hnew : (⟨room, a.name, a.clock, body⟩ : Msg) ∉ a.spool)
    (hv : (⟨room, a.name, a.clock, body⟩ : Msg) ∉ v.spool) :
    (⟨room, a.name, a.clock, body⟩ : Msg) ∉ ((s.publish path a).visit path v).spool := by
  intro hmem
  unfold visit publish at hmem
  rw [get_put_self] at hmem
  rcases Node.mem_paste_iff.mp hmem with h | ⟨ms, hms, h⟩
  · exact hv h
  · rw [openBag_bag ha, Option.some.injEq] at hms
    have hv : (⟨room, a.name, a.clock, body⟩ : Msg) ∈ a.view := by rw [hms]; exact h
    exact hnew (mem_transcript.mp hv)

/-- The message the publisher writes after the snapshot really is new to
them, and reaches the visitor as soon as a fresher page is pasted. -/
theorem fresh_code_catches_up {s : Site} {path : List Char} {a v : Node} {room : List Char}
    {body : Blob} (ha : Node.Wired (a.write room body)) :
    (⟨room, a.name, a.clock, body⟩ : Msg)
      ∈ ((s.publish path (a.write room body)).visit path v).spool := by
  refine visitor_catches_up ha ?_
  exact mem_absorb_iff.mpr (Or.inr (by simp))

end Site

end Kant.Uucp
