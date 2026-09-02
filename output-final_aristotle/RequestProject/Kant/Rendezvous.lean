/-
# Finding other clients: peers, rosters, gossip and the chat QR code

Two browsers that have never met need three things to talk: a *room* they
agree on, an *address list* for each other, and a way to hand the first
of those over out of band.  This module specifies all three.

* A **peer announcement** (`Announce`) says "peer `p`, at revision `seq`,
  can be reached at these addresses" — an address being any transport the
  replication layer already understands (`Kant.Sync.Source`: a relay URL,
  an iroh ticket, a libp2p multiaddr, an IPFS gateway, …).
* A **roster** is the grow-only set of announcements a client has heard.
  Clients gossip rosters at each other; `Roster.best` picks the freshest
  announcement for a peer.
* An **invite** is what the chat QR code contains: the relay to meet at,
  a shared secret, the inviter's own id and its direct addresses.  The
  room is the digest of the secret, so *scanning the same code puts both
  clients in the same room* while the relay only ever learns the digest.

Proved here:

* `parseAnnounce_printAnnounce` — an announcement survives the wire;
* `mem_merge_iff` — a client's roster after gossip is exactly what it knew
  plus what it heard, so gossip never loses a peer (`merge_preserves`) and
  never invents one;
* `merge_perm` — the roster is a set: the order in which announcements
  arrive is irrelevant;
* `best_spec` / `best_congr` — the freshest announcement for a peer is
  well defined and depends only on the *set* of announcements heard,
  hence two clients that heard the same things dial the same address;
* `discovery_transitive` — if A gossips with B and B had gossiped with C,
  A learns everybody C advertised: discovery is transitive;
* `pasteInvite_copyInvite`, `pasteInviteUrl_inviteUrl` — the chat QR
  payload (and the equivalent link) reads back as the same invite;
* `scan_same_room` — two clients scanning one code compute one room;
* `invite_fits_qr` — the payload fits in a single QR code.
-/
import Mathlib
import RequestProject.Kant.Bytes
import RequestProject.Kant.Text
import RequestProject.Kant.Clipboard
import RequestProject.Kant.Sneakernet
import RequestProject.Kant.Sync

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.Rendezvous

open Kant Kant.Bytes Kant.Text Kant.Clipboard Kant.Sync

/-! ## Addresses -/

/-- Where a peer can be reached: a transport, and a locator understood by
that transport (an `https://` relay, an iroh ticket, a multiaddr, a CID…). -/
structure Address where
  /-- Which transport the locator belongs to. -/
  transport : Source
  /-- The transport-specific locator. -/
  locator : List Char
deriving DecidableEq, Repr

/-- One byte naming a transport, for the wire format. -/
def sourceCode : Source → UInt8
  | .ipfs => 1
  | .iroh => 2
  | .libp2p => 3
  | .torrent => 4
  | .archiveOrg => 5
  | .uucp => 6
  | .qrBurst => 7
  | .localDisk => 8

/-- Read a transport byte. -/
def sourceOfCode : UInt8 → Option Source
  | 1 => some .ipfs
  | 2 => some .iroh
  | 3 => some .libp2p
  | 4 => some .torrent
  | 5 => some .archiveOrg
  | 6 => some .uucp
  | 7 => some .qrBurst
  | 8 => some .localDisk
  | _ => none

@[simp] theorem sourceOfCode_sourceCode (s : Source) : sourceOfCode (sourceCode s) = some s := by
  cases s <;> rfl

/-- An address as one byte field. -/
def addrField (a : Address) : Blob := sourceCode a.transport :: asciiBytes a.locator

/-- Read an address back out of a byte field. -/
def parseAddrField : Blob → Option Address
  | [] => none
  | c :: bs => (sourceOfCode c).map (fun t => ⟨t, asciiChars bs⟩)

/-- Addresses survive the wire format. -/
theorem parseAddrField_addrField {a : Address} (h : IsAscii a.locator) :
    parseAddrField (addrField a) = some a := by
  cases a with
  | mk t l =>
      simp only [addrField, parseAddrField, sourceOfCode_sourceCode, Option.map_some,
        Option.some.injEq]
      simp [asciiChars_asciiBytes h]

/-- Read a list of address fields. -/
def parseAddrFields : List Blob → Option (List Address)
  | [] => some []
  | f :: fs =>
      match parseAddrField f, parseAddrFields fs with
      | some a, some as => some (a :: as)
      | _, _ => none

theorem parseAddrFields_map {as : List Address} (h : ∀ a ∈ as, IsAscii a.locator) :
    parseAddrFields (as.map addrField) = some as := by
  induction as with
  | nil => rfl
  | cons a as ih =>
      have ha : IsAscii a.locator := h a (by simp)
      have hrest : ∀ b ∈ as, IsAscii b.locator := fun b hb => h b (by simp [hb])
      simp [parseAddrFields, parseAddrField_addrField ha, ih hrest]

/-! ## Announcements -/

/-- "Peer `peer`, at revision `seq`, can be reached at `addrs`." -/
structure Announce where
  /-- The stable identifier of the peer. -/
  peer : List Char
  /-- A counter the peer bumps every time it re-announces itself. -/
  seq : Nat
  /-- The addresses the peer is currently offering. -/
  addrs : List Address
deriving DecidableEq, Repr

/-- An announcement is transmissible when its text fields are ASCII. -/
structure Announce.Wire (a : Announce) : Prop where
  /-- The peer identifier is ASCII. -/
  peer : IsAscii a.peer
  /-- Every locator is ASCII. -/
  addrs : ∀ x ∈ a.addrs, IsAscii x.locator

/-- Tag of an announcement on the wire. -/
def tagPeer : Blob := asciiBytes "kzpeer".toList

/-- An announcement as a copyable envelope. -/
def ofAnnounce (a : Announce) : Envelope :=
  ⟨tagPeer, asciiBytes a.peer :: natToBytesBE a.seq :: a.addrs.map addrField⟩

/-- Read an announcement back out of an envelope. -/
def toAnnounce (e : Envelope) : Option Announce :=
  if e.tag ≠ tagPeer then none
  else
    match e.fields with
    | p :: s :: rest =>
        (parseAddrFields rest).map (fun as => ⟨asciiChars p, bytesBEToNat s, as⟩)
    | _ => none

/-- An announcement as one line of text: what a client posts to a relay,
gossips over a data channel, or hides in a picture. -/
def printAnnounce (a : Announce) : List Char := (ofAnnounce a).encode

/-- Read an announcement off the wire. -/
def parseAnnounce (s : List Char) : Option Announce := (Envelope.decode s).bind toAnnounce

/-- **An announcement survives the wire.** -/
theorem parseAnnounce_printAnnounce {a : Announce} (h : a.Wire) :
    parseAnnounce (printAnnounce a) = some a := by
  unfold parseAnnounce printAnnounce
  rw [Envelope.decode_encode]
  cases a with
  | mk p s as =>
      simp only [Option.bind_some, toAnnounce, ofAnnounce, ne_eq, not_true_eq_false, if_false,
        parseAddrFields_map h.addrs, Option.map_some,
        asciiChars_asciiBytes h.peer, bytesBEToNat_natToBytesBE]

/-- Announcement text is plain ASCII, so it fits in a QR code, a chat
window or a URL. -/
theorem isAscii_printAnnounce (a : Announce) : IsAscii (printAnnounce a) :=
  Envelope.isAscii_encode _

/-! ## Rosters and gossip -/

/-- What a client knows about the network: a grow-only set of
announcements. -/
abbrev Roster := List Announce

namespace Roster

/-- Record an announcement.  Hearing the same one twice changes nothing. -/
def insert (r : Roster) (a : Announce) : Roster := if a ∈ r then r else a :: r

/-- Fold a batch of announcements into a roster: one gossip exchange, one
relay poll, one QR scan. -/
def merge (r : Roster) (as : List Announce) : Roster := as.foldl insert r

@[simp] theorem merge_nil (r : Roster) : merge r [] = r := rfl

@[simp] theorem merge_cons (r : Roster) (a : Announce) (as : List Announce) :
    merge r (a :: as) = merge (insert r a) as := rfl

@[simp] theorem mem_insert {r : Roster} {a x : Announce} : x ∈ insert r a ↔ x ∈ r ∨ x = a := by
  unfold insert
  by_cases h : a ∈ r
  · simp only [h, if_true]
    constructor
    · exact Or.inl
    · rintro (hx | rfl) <;> simp_all
  · simp [h, or_comm]

/-- **A roster after gossip is exactly what was known plus what was
heard**: nothing is lost and nothing is invented. -/
theorem mem_merge_iff {r : Roster} {as : List Announce} {x : Announce} :
    x ∈ merge r as ↔ x ∈ r ∨ x ∈ as := by
  induction as generalizing r with
  | nil => simp
  | cons a as ih =>
      rw [merge_cons, ih]
      simp only [mem_insert, List.mem_cons]
      tauto

/-- Gossip never forgets a peer. -/
theorem merge_preserves {r : Roster} {as : List Announce} {x : Announce} (h : x ∈ r) :
    x ∈ merge r as := mem_merge_iff.mpr (Or.inl h)

/-- Everything heard is recorded. -/
theorem merge_delivers {r : Roster} {as : List Announce} {x : Announce} (h : x ∈ as) :
    x ∈ merge r as := mem_merge_iff.mpr (Or.inr h)

/-- **Order does not matter.**  Announcements arriving from a relay, a
data channel and a QR scan in any interleaving give the same roster. -/
theorem merge_perm {r : Roster} {as bs : List Announce} (h : as.Perm bs) (x : Announce) :
    x ∈ merge r as ↔ x ∈ merge r bs := by
  rw [mem_merge_iff, mem_merge_iff, h.mem_iff]

/-- Re-merging what is already known adds nothing. -/
theorem merge_idem {r : Roster} {as : List Announce} (x : Announce) :
    x ∈ merge (merge r as) as ↔ x ∈ merge r as := by
  rw [mem_merge_iff, mem_merge_iff]
  tauto

/-- **Discovery is transitive.**  If C told B about somebody and B then
gossips with A, A learns about them too. -/
theorem discovery_transitive (A B C : Roster) : ∀ x ∈ C, x ∈ merge A (merge B C) :=
  fun _ hx => merge_delivers (merge_delivers hx)

/-- Does the client know any address for this peer? -/
def knows (r : Roster) (p : List Char) : Bool := r.any (fun a => a.peer == p)

theorem knows_iff {r : Roster} {p : List Char} :
    knows r p = true ↔ ∃ a ∈ r, a.peer = p := by
  simp [knows]

/-- After gossip, a client knows every peer either side knew. -/
theorem knows_merge_iff {r : Roster} {as : List Announce} {p : List Char} :
    knows (merge r as) p = true ↔ (knows r p = true ∨ ∃ a ∈ as, a.peer = p) := by
  simp only [knows_iff]
  constructor
  · rintro ⟨a, ha, rfl⟩
    rcases mem_merge_iff.mp ha with h | h
    · exact Or.inl ⟨a, h, rfl⟩
    · exact Or.inr ⟨a, h, rfl⟩
  · rintro (⟨a, ha, rfl⟩ | ⟨a, ha, rfl⟩)
    · exact ⟨a, merge_preserves ha, rfl⟩
    · exact ⟨a, merge_delivers ha, rfl⟩

end Roster

/-! ## The freshest address for a peer

A peer moves: it gets a new relay, a new iroh ticket, a new tab.  Each
announcement carries a counter, and a client dials the announcement with
the greatest counter it has heard. -/

/-- Pick the entry with the greatest counter, `none` for an empty list. -/
def bestOf : List Announce → Option Announce
  | [] => none
  | a :: as =>
      match bestOf as with
      | none => some a
      | some b => if b.seq < a.seq then some a else some b

/-- The freshest announcement a client holds for a peer. -/
def Roster.best (r : Roster) (p : List Char) : Option Announce :=
  bestOf (r.filter (fun a => a.peer == p))

theorem bestOf_eq_none_iff {l : List Announce} : bestOf l = none ↔ l = [] := by
  cases l with
  | nil => simp [bestOf]
  | cons a as =>
      simp only [bestOf, List.cons_ne_nil, iff_false]
      cases h : bestOf as with
      | none => simp
      | some b => by_cases hb : b.seq < a.seq <;> simp [hb]

theorem bestOf_mem {l : List Announce} {a : Announce} (h : bestOf l = some a) : a ∈ l := by
  induction l with
  | nil => simp [bestOf] at h
  | cons x xs ih =>
      cases hb : bestOf xs with
      | none =>
          simp only [bestOf, hb, Option.some.injEq] at h
          simp [h]
      | some b =>
          simp only [bestOf, hb] at h
          by_cases hlt : b.seq < x.seq
          · rw [if_pos hlt] at h
            simp only [Option.some.injEq] at h
            simp [h]
          · rw [if_neg hlt] at h
            simp only [Option.some.injEq] at h
            exact List.mem_cons_of_mem _ (ih (h ▸ hb))

theorem bestOf_max : ∀ {l : List Announce} {a : Announce}, bestOf l = some a →
    ∀ b ∈ l, b.seq ≤ a.seq := by
  intro l
  induction l with
  | nil => intro a h; simp [bestOf] at h
  | cons x xs ih =>
      intro a h
      cases hb : bestOf xs with
      | none =>
          have hxs : xs = [] := bestOf_eq_none_iff.mp hb
          simp only [bestOf, hb, Option.some.injEq] at h
          subst h; subst hxs
          simp
      | some b =>
          simp only [bestOf, hb] at h
          by_cases hlt : b.seq < x.seq
          · rw [if_pos hlt] at h
            simp only [Option.some.injEq] at h
            subst h
            intro y hy
            rcases List.mem_cons.mp hy with rfl | hy'
            · exact le_rfl
            · exact le_trans (ih hb y hy') (le_of_lt hlt)
          · rw [if_neg hlt] at h
            simp only [Option.some.injEq] at h
            subst h
            intro y hy
            rcases List.mem_cons.mp hy with rfl | hy'
            · omega
            · exact ih hb y hy'

/-- What it means to be the announcement a client should dial. -/
structure IsBest (r : Roster) (p : List Char) (a : Announce) : Prop where
  /-- It was actually heard. -/
  mem : a ∈ r
  /-- It is about the right peer. -/
  peer : a.peer = p
  /-- Nothing fresher about that peer was heard. -/
  greatest : ∀ b ∈ r, b.peer = p → b.seq ≤ a.seq

/-- **`best` really does return the freshest announcement heard.** -/
theorem best_spec {r : Roster} {p : List Char} {a : Announce} (h : r.best p = some a) :
    IsBest r p a := by
  unfold Roster.best at h
  have hmem := bestOf_mem h
  have hmax := bestOf_max h
  simp only [List.mem_filter, beq_iff_eq] at hmem
  exact ⟨hmem.1, hmem.2, fun b hb hbp => hmax b (by simp [List.mem_filter, hb, hbp])⟩

/-- `best` only fails when nothing at all was heard about the peer. -/
theorem best_eq_none_iff {r : Roster} {p : List Char} :
    r.best p = none ↔ ∀ a ∈ r, a.peer ≠ p := by
  unfold Roster.best
  rw [bestOf_eq_none_iff, List.filter_eq_nil_iff]
  simp

/-- If the peer is known at all, `best` returns something. -/
theorem best_isSome_of_knows {r : Roster} {p : List Char} (h : Roster.knows r p = true) :
    ∃ a, r.best p = some a := by
  obtain ⟨b, hb, hbp⟩ := Roster.knows_iff.mp h
  cases hbest : r.best p with
  | none => exact absurd hbp (best_eq_none_iff.mp hbest b hb)
  | some a => exact ⟨a, rfl⟩

/-- Peers do not contradict themselves: one announcement per revision. -/
def Coherent (r : Roster) : Prop :=
  ∀ a ∈ r, ∀ b ∈ r, a.peer = b.peer → a.seq = b.seq → a = b

theorem isBest_unique {r : Roster} (hc : Coherent r) {p : List Char} {a b : Announce}
    (ha : IsBest r p a) (hb : IsBest r p b) : a = b := by
  have h₁ : a.seq ≤ b.seq := hb.greatest a ha.mem ha.peer
  have h₂ : b.seq ≤ a.seq := ha.greatest b hb.mem hb.peer
  exact hc a ha.mem b hb.mem (ha.peer.trans hb.peer.symm) (le_antisymm h₁ h₂)

/-- **Two clients that heard the same announcements dial the same
address**, whatever route or order the announcements took. -/
theorem best_congr {r₁ r₂ : Roster} (hc : Coherent r₁) (hmem : ∀ x, x ∈ r₁ ↔ x ∈ r₂)
    (p : List Char) : r₁.best p = r₂.best p := by
  have hc₂ : Coherent r₂ := by
    intro a ha b hb hp hs
    exact hc a ((hmem a).mpr ha) b ((hmem b).mpr hb) hp hs
  have transfer : ∀ {s t : Roster}, (∀ x, x ∈ s ↔ x ∈ t) → ∀ {a}, IsBest s p a → IsBest t p a := by
    intro s t h a hbest
    exact ⟨(h a).mp hbest.mem, hbest.peer,
      fun b hb hbp => hbest.greatest b ((h b).mpr hb) hbp⟩
  cases h₁ : r₁.best p with
  | none =>
      cases h₂ : r₂.best p with
      | none => rfl
      | some b =>
          exact absurd (best_spec h₂).peer
            (best_eq_none_iff.mp h₁ b ((hmem b).mpr (best_spec h₂).mem))
  | some a =>
      have hA : IsBest r₂ p a := transfer hmem (best_spec h₁)
      cases h₂ : r₂.best p with
      | none => exact absurd hA.peer (best_eq_none_iff.mp h₂ a hA.mem)
      | some b => rw [isBest_unique hc₂ hA (best_spec h₂)]

/-- The freshest address survives gossip in either direction. -/
theorem best_merge_of_perm {r : Roster} {as bs : List Announce} (hperm : as.Perm bs)
    (hc : Coherent (Roster.merge r as)) (p : List Char) :
    (Roster.merge r as).best p = (Roster.merge r bs).best p :=
  best_congr hc (fun x => Roster.merge_perm hperm x) p

/-! ## The chat QR code

The out-of-band step.  One client shows a code; the other scans it.  The
code carries the relay to meet at, a shared secret, the inviter's id and
whatever direct addresses it already has.  The *room* is the digest of
the secret: both sides compute it, and a relay that only sees the room
never sees the secret it came from. -/

/-- The room named by a shared secret: 64 hex characters. -/
def roomOf (secret : Blob) : List Char := Kant.Bytes.witness secret

@[simp] theorem roomOf_length (secret : Blob) : (roomOf secret).length = 64 :=
  Kant.Bytes.witness_length _

/-- Rooms are ASCII, so a room name travels anywhere. -/
theorem isAscii_roomOf (secret : Blob) : IsAscii (roomOf secret) :=
  isAscii_hexEncode _

/-- **The same secret names the same room** for everybody. -/
theorem roomOf_congr {s t : Blob} (h : s = t) : roomOf s = roomOf t := by rw [h]

/-- What a chat QR code contains. -/
structure Invite where
  /-- The rendezvous server both clients will poll. -/
  relay : List Char
  /-- The shared secret; its digest is the room. -/
  secret : Blob
  /-- The peer offering the invitation. -/
  peer : List Char
  /-- Direct addresses to try before falling back to the relay. -/
  addrs : List Address
deriving DecidableEq, Repr

/-- The room this invitation leads to. -/
def Invite.room (i : Invite) : List Char := roomOf i.secret

/-- An invitation is transmissible when its text fields are ASCII. -/
structure Invite.Wire (i : Invite) : Prop where
  /-- The relay URL is ASCII. -/
  relay : IsAscii i.relay
  /-- The peer identifier is ASCII. -/
  peer : IsAscii i.peer
  /-- Every locator is ASCII. -/
  addrs : ∀ x ∈ i.addrs, IsAscii x.locator

/-- Tag of an invitation. -/
def tagInvite : Blob := asciiBytes "kzinvite".toList

/-- An invitation as an envelope. -/
def ofInvite (i : Invite) : Envelope :=
  ⟨tagInvite, asciiBytes i.relay :: i.secret :: asciiBytes i.peer :: i.addrs.map addrField⟩

/-- Read an invitation back out of an envelope. -/
def toInvite (e : Envelope) : Option Invite :=
  if e.tag ≠ tagInvite then none
  else
    match e.fields with
    | r :: s :: p :: rest =>
        (parseAddrFields rest).map (fun as => ⟨asciiChars r, s, asciiChars p, as⟩)
    | _ => none

/-- The text a chat QR code carries. -/
def copyInvite (i : Invite) : List Char := (ofInvite i).encode

/-- Read a scanned or pasted invitation. -/
def pasteInvite (s : List Char) : Option Invite := (Envelope.decode s).bind toInvite

/-- **A scanned invitation is the invitation that was shown.** -/
theorem pasteInvite_copyInvite {i : Invite} (h : i.Wire) : pasteInvite (copyInvite i) = some i := by
  unfold pasteInvite copyInvite
  rw [Envelope.decode_encode]
  cases i with
  | mk r s p as =>
      simp only [Option.bind_some, toInvite, ofInvite, ne_eq, not_true_eq_false, if_false,
        parseAddrFields_map h.addrs, Option.map_some,
        asciiChars_asciiBytes h.relay, asciiChars_asciiBytes h.peer]

/-- **Both clients land in the same room.**  Whoever scans the code
computes the room the inviter meant, without the code ever naming it. -/
theorem scan_same_room {i j : Invite} (h : i.Wire) (hj : pasteInvite (copyInvite i) = some j) :
    j.room = i.room := by
  rw [pasteInvite_copyInvite h] at hj
  simp only [Option.some.injEq] at hj
  rw [hj]

/-- The same invitation as a link, for people who cannot scan. -/
def inviteUrl (base : List Char) (i : Invite) : List Char := shareUrl base (ofInvite i)

/-- Read an invitation out of a link. -/
def parseInviteUrl (u : List Char) : Option Invite := (parseShareUrl u).bind toInvite

/-- **An invite link works exactly like the QR code.** -/
theorem parseInviteUrl_inviteUrl {base : List Char} (hb : hash ∉ base) {i : Invite} (h : i.Wire) :
    parseInviteUrl (inviteUrl base i) = some i := by
  unfold parseInviteUrl inviteUrl
  rw [parseShareUrl_shareUrl hb]
  have := pasteInvite_copyInvite h
  unfold pasteInvite copyInvite at this
  rw [Envelope.decode_encode] at this
  simpa using this

/-- Invite text is ASCII: it survives a QR code, a chat window, a URL or
a picture caption. -/
theorem isAscii_copyInvite (i : Invite) : IsAscii (copyInvite i) := Envelope.isAscii_encode _

/-! ### Size: one code, one scan -/

theorem joinFields_length_le (fs : List (List Char)) :
    (joinFields fs).length ≤ (fs.map List.length).sum + fs.length := by
  induction fs with
  | nil => simp [joinFields]
  | cons f fs ih =>
      cases fs with
      | nil => simp [joinFields]
      | cons g gs =>
          rw [show joinFields (f :: g :: gs) = f ++ sep :: joinFields (g :: gs) from rfl]
          simp only [List.length_append, List.length_cons, List.map_cons, List.sum_cons] at ih ⊢
          omega

theorem Envelope.encode_length_le (e : Envelope) :
    e.encode.length ≤ 2 * (e.tag.length + (e.fields.map List.length).sum) + e.fields.length + 1 := by
  have h := joinFields_length_le ((e.tag :: e.fields).map hexEncode)
  have hmap : (((e.tag :: e.fields).map hexEncode).map List.length).sum
      = 2 * (e.tag.length + (e.fields.map List.length).sum) := by
    induction e.fields with
    | nil => simp [hexEncode_length]
    | cons f fs ih =>
        simp only [List.map_cons, List.sum_cons, hexEncode_length] at ih ⊢
        omega
  simp only [Envelope.encode, List.length_cons, List.length_map] at h ⊢
  omega

/-- **A chat invitation fits in one QR code.**  With a relay URL, a
secret, an identifier and a handful of addresses — 1400 bytes of payload
across at most a hundred fields — the printed text stays inside the
binary capacity of a version-40 QR code. -/
theorem invite_fits_qr {i : Invite}
    (hsum : (((ofInvite i).fields).map List.length).sum ≤ 1400)
    (hn : ((ofInvite i).fields).length ≤ 100) :
    (copyInvite i).length ≤ Kant.Sneakernet.Channel.qr.capacity := by
  have h := Envelope.encode_length_le (ofInvite i)
  have htag : (ofInvite i).tag.length = 8 := rfl
  simp only [copyInvite, htag] at h ⊢
  have hcap : Kant.Sneakernet.Channel.qr.capacity = 2953 := rfl
  omega

/-! ## Putting it together: two strangers meet

`meet` is what a client does with a scanned code: it records the
inviter's announcement and joins the room.  The theorems say that after
scanning, the scanner can dial the inviter, and that both sides agree on
where they are. -/

/-- The announcement carried implicitly by an invitation. -/
def Invite.announce (i : Invite) : Announce := ⟨i.peer, 0, i.addrs⟩

/-- Scanning a code: join the room, record the inviter. -/
def meet (r : Roster) (i : Invite) : List Char × Roster :=
  (i.room, Roster.insert r i.announce)

/-- **After scanning, the scanner knows how to reach the inviter.** -/
theorem meet_knows (r : Roster) (i : Invite) :
    Roster.knows (meet r i).2 i.peer = true := by
  refine Roster.knows_iff.mpr ⟨i.announce, ?_, rfl⟩
  exact Roster.mem_insert.mpr (Or.inr rfl)

/-- Scanning never drops peers already known. -/
theorem meet_preserves {r : Roster} {x : Announce} (i : Invite) (h : x ∈ r) :
    x ∈ (meet r i).2 := Roster.mem_insert.mpr (Or.inl h)

/-- **Both sides of the code are in the same room.** -/
theorem meet_room (r : Roster) (i : Invite) : (meet r i).1 = i.room := rfl

end Kant.Rendezvous
