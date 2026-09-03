/-
# Two cards will never connect: what a pasted code actually is

Somebody pasted two blocks of text that look like this

```
kant-zk-pastebin
https://kant.cicada71.net/#ff81…f605
6b7a63617264:6874747073…:6b616e742d7a6b2d706173746562696e:2e2f…
```

and reported that "they are not connecting".  This module says, and
proves, what such a block *is* and what it can therefore do.

`classify` reads the last non-blank line of a pasted block and decides
between the three codes this system hands out:

* a **card** (`kzcard:…`) — a page URL, a caption and a picture;
* an **invitation** (`kzinvite:…`) — a relay and a shared secret, whose
  digest is the room two clients meet in;
* a bare **page link** — `<origin>#<64 hex>`, an address and nothing else.

The diagnosis:

* `card_no_room`, `page_no_room` — a card and a page link name *no room*
  at all.  There is nothing in them to connect to, which is why no log
  ever mentioned a connection attempt: none was made.
* `pair_not_connectable_of_card_left` / `…_right` — pairing a card with
  anything is never `connectable`.
* `pair_same_card` — pairing a card with *itself* is reported as
  `sameCode`: the two blocks in the report decode to one and the same
  card, so they are one object, not two endpoints.
* `userCard_classify`, `userCard_pair`, `userCard_no_room` — the exact
  text from the report, run through the classifier.
* `pair_connectable_iff` — what it takes instead: two *invitations*, the
  same room, the same non-empty relay.
* `connectable_linked` — and that those two invitations really do put two
  clients in touch, in the sense of `Kant.Connectivity.Linked`.
* `configured_relay_links` — the deployment fix: a `relay =` that both
  sides can reach links them, which the shipped blank `relay =` and a
  static origin provably cannot (`static_deployment_stuck`).
* `explain_injective` — six outcomes, six different sentences.
-/
import Mathlib
import RequestProject.Kant.Bytes
import RequestProject.Kant.Text
import RequestProject.Kant.Clipboard
import RequestProject.Kant.Rendezvous
import RequestProject.Kant.SiteCard
import RequestProject.Kant.Connectivity

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.CardDebug

open Kant Kant.Bytes Kant.Text

/-! ## Reading a pasted block -/

/-- Whitespace that survives a copy and paste. -/
def blank (c : Char) : Bool := c = ' ' || c = '\t' || c = '\r'

/-- Drop the spaces at both ends of a line. -/
def trim (s : List Char) : List Char :=
  ((s.dropWhile blank).reverse.dropWhile blank).reverse

/-- The line a pasted block's meaning is in: the last non-blank one.  A
card pasted as text is caption, link, then the machine-readable line; a
bare code is that line on its own; a link is the link. -/
def codeLine (s : List Char) : List Char :=
  (((Kant.SiteCard.splitCh '\n' s).map trim).filter (fun l => !l.isEmpty)).getLastD []

/-- A line of text as an envelope: either it *is* one, or it is a URL
whose fragment is one. -/
def envelopeOf (l : List Char) : Option Kant.Clipboard.Envelope :=
  match Kant.Clipboard.Envelope.decode l with
  | some e => some e
  | none => Kant.Clipboard.parseShareUrl l

/-- Is this a lower-case hex digit? -/
def isHex (c : Char) : Bool := ('0' ≤ c && c ≤ '9') || ('a' ≤ c && c ≤ 'f')

/-- A content address: exactly 64 hex characters. -/
def isAddress (f : List Char) : Bool := f.length = 64 && f.all isHex

/-- What a pasted block turns out to be. -/
inductive Code where
  /-- A share card: a page, a caption, a picture.  Carries no room. -/
  | card (k : Kant.SiteCard.Card) : Code
  /-- An invitation: a relay and a secret whose digest is a room. -/
  | invite (i : Kant.Rendezvous.Invite) : Code
  /-- A bare page link: `<origin>#<64 hex>`. -/
  | page (addr : List Char) : Code
  /-- Not a code this system issued. -/
  | unknown : Code
deriving DecidableEq, Repr

/-- An envelope is one of our codes when it is a card or an invitation.
Anything else - including the bare 32-byte field a page link's fragment
happens to decode to - is not. -/
def codeOfEnvelope (e : Kant.Clipboard.Envelope) : Option Code :=
  match Kant.SiteCard.toCard e with
  | some k => some (.card k)
  | none => (Kant.Rendezvous.toInvite e).map Code.invite

/-- Read a pasted block: a card or an invitation if the last line carries
one, else a page link if it is one, else nothing we issued. -/
def classify (s : List Char) : Code :=
  let l := codeLine s
  match (envelopeOf l).bind codeOfEnvelope with
  | some c => c
  | none =>
      let f := Kant.Clipboard.fragment l
      if isAddress f then .page f else .unknown

/-- The room a pasted code leads to, if any. -/
def roomOf? : Code → Option (List Char)
  | .invite i => some i.room
  | _ => none

/-- The relay a pasted code names, if any. -/
def relayOf? : Code → Option (List Char)
  | .invite i => some i.relay
  | _ => none

/-- **A card names no room.**  There is nothing in a card to connect to. -/
@[simp] theorem card_no_room (k : Kant.SiteCard.Card) : roomOf? (.card k) = none := rfl

/-- **A page link names no room either.** -/
@[simp] theorem page_no_room (a : List Char) : roomOf? (.page a) = none := rfl

@[simp] theorem unknown_no_room : roomOf? .unknown = none := rfl

/-- **Only an invitation names a room**, and it is the digest of its
secret. -/
@[simp] theorem invite_room (i : Kant.Rendezvous.Invite) : roomOf? (.invite i) = some i.room := rfl

/-- A card names no relay to meet at. -/
@[simp] theorem card_no_relay (k : Kant.SiteCard.Card) : relayOf? (.card k) = none := rfl

/-- Rooms are never empty: they are 64 hex characters. -/
theorem invite_room_ne_nil (i : Kant.Rendezvous.Invite) : i.room ≠ [] := by
  intro h
  have := Kant.Rendezvous.roomOf_length i.secret
  rw [show Kant.Rendezvous.roomOf i.secret = i.room from rfl, h] at this
  simp at this

/-! ## Pairing two pasted blocks -/

/-- The outcome of holding two pasted blocks up against each other. -/
inductive Pairing where
  /-- Two invitations, one room, one relay: these two can meet. -/
  | connectable : Pairing
  /-- The two blocks are the very same code — one object, not two. -/
  | sameCode : Pairing
  /-- Neither block is an invitation: nothing here to connect. -/
  | notInvites : Pairing
  /-- One is an invitation and the other is not. -/
  | oneNotInvite : Pairing
  /-- Two invitations, but to different rooms. -/
  | differentRooms : Pairing
  /-- Two invitations to one room, but no relay, or not the same one. -/
  | noMeetingPoint : Pairing
deriving DecidableEq, Repr

/-- Diagnose two codes. -/
def pairCodes : Code → Code → Pairing
  | .invite a, .invite b =>
      if a.room ≠ b.room then .differentRooms
      else if a.relay = [] ∨ a.relay ≠ b.relay then .noMeetingPoint
      else .connectable
  | .invite _, _ => .oneNotInvite
  | _, .invite _ => .oneNotInvite
  | u, v => if u = v then .sameCode else .notInvites

/-- Diagnose two pasted blocks. -/
def pair (x y : List Char) : Pairing := pairCodes (classify x) (classify y)

/-- **What it takes for two codes to connect**: both are invitations,
they agree on the room, and they name one and the same non-empty
relay. -/
theorem pairCodes_invite_connectable_iff (a b : Kant.Rendezvous.Invite) :
    pairCodes (.invite a) (.invite b) = .connectable ↔
      a.room = b.room ∧ a.relay ≠ [] ∧ a.relay = b.relay := by
  simp only [pairCodes]
  by_cases hr : a.room = b.room
  · simp only [ne_eq, hr, not_true_eq_false, if_false]
    by_cases h1 : a.relay = []
    · simp [h1]
    · by_cases h2 : a.relay = b.relay
      · simp [h2]
      · simp [h1, h2]
  · simp [hr]

theorem pairCodes_connectable_iff (u v : Code) :
    pairCodes u v = .connectable ↔
      ∃ a b, u = .invite a ∧ v = .invite b ∧
        a.room = b.room ∧ a.relay ≠ [] ∧ a.relay = b.relay := by
  cases u <;> cases v
  case invite.invite a b => simpa using pairCodes_invite_connectable_iff a b
  all_goals (simp only [pairCodes]; try split_ifs)
  all_goals simp_all

/-- Nothing but an invitation can connect. -/
theorem pairCodes_not_connectable_left {u v : Code} (h : ∀ i, u ≠ .invite i) :
    pairCodes u v ≠ .connectable := by
  intro hc
  obtain ⟨a, _, hu, _⟩ := (pairCodes_connectable_iff u v).1 hc
  exact h a hu

/-- Nothing but an invitation can connect, on either side. -/
theorem pairCodes_not_connectable_right {u v : Code} (h : ∀ i, v ≠ .invite i) :
    pairCodes u v ≠ .connectable := by
  intro hc
  obtain ⟨_, b, _, hv, _⟩ := (pairCodes_connectable_iff u v).1 hc
  exact h b hv

/-- **A card on the left can never connect.** -/
theorem pair_not_connectable_of_card_left {x y : List Char} {k : Kant.SiteCard.Card}
    (h : classify x = .card k) : pair x y ≠ .connectable :=
  pairCodes_not_connectable_left (by rw [h]; intro i; simp)

/-- **A card on the right can never connect either.** -/
theorem pair_not_connectable_of_card_right {x y : List Char} {k : Kant.SiteCard.Card}
    (h : classify y = .card k) : pair x y ≠ .connectable :=
  pairCodes_not_connectable_right (by rw [h]; intro i; simp)

/-- **A bare page link can never connect either**: it names an address,
not a room. -/
theorem pair_not_connectable_of_page_left {x y : List Char} {addr : List Char}
    (h : classify x = .page addr) : pair x y ≠ .connectable :=
  pairCodes_not_connectable_left (by rw [h]; intro i; simp)

/-- **Two copies of one card are one object.**  Pasting the same card
twice is reported as such, rather than as a failed connection. -/
theorem pair_same_card {x y : List Char} {k : Kant.SiteCard.Card}
    (hx : classify x = .card k) (hy : classify y = .card k) : pair x y = .sameCode := by
  unfold pair pairCodes
  rw [hx, hy]
  simp

/-- **What it actually takes**: two invitations, the same room, and one
non-empty relay named by both. -/
theorem pair_connectable_iff (x y : List Char) :
    pair x y = .connectable ↔
      ∃ a b, classify x = .invite a ∧ classify y = .invite b ∧
        a.room = b.room ∧ a.relay ≠ [] ∧ a.relay = b.relay :=
  pairCodes_connectable_iff _ _

/-! ## From two invitations to two clients that really talk -/

open Kant.Connectivity

/-- **A relay both sides can reach links them.**  This is the deployment
fix: put a reachable relay in `relay =` and two devices meet, wherever
the page itself is hosted. -/
theorem configured_relay_links {a b : Client} {R : List Char}
    (hroom : a.room = b.room) (hne : a.room ≠ []) (hR : R ≠ [])
    (hca : a.reach.configured = R) (hcb : b.reach.configured = R)
    (hua : a.reach.configuredUp = true) (hub : b.reach.configuredUp = true) :
    Linked a b := by
  have hane : a.reach.configured ≠ [] := by rw [hca]; exact hR
  have hbne : b.reach.configured ≠ [] := by rw [hcb]; exact hR
  refine ⟨hroom, hne, Or.inr ⟨?_, ?_, ?_, ?_⟩⟩
  · simp [RelayUsable, hane, hua]
  · simp [RelayUsable, hbne, hub]
  · rw [effectiveRelay_configured hane, hca]; exact hR
  · rw [effectiveRelay_configured hane, effectiveRelay_configured hbne, hca, hcb]

/-- **The shipped deployment cannot do it.**  `relay =` blank and a plain
static origin (which does not answer `/health` as a relay) leaves two
browsers with no transport whatever, however correct the code they
scanned.  This is `Kant.Connectivity.two_browsers_one_machine_stuck`
restated as the deployment's own verdict. -/
theorem static_deployment_stuck {a b : Client}
    (hca : a.reach.configured = []) (hoa : a.reach.originIsRelay = false)
    (hdiff : a.browser ≠ b.browser) : ¬ Linked a b :=
  two_browsers_one_machine_stuck hca hoa hdiff

/-- **A connectable pair really is a connection.**  If two people paste
two invitations that this module calls `connectable`, and each client
uses the relay its invitation named and that relay answers, then the two
clients can exchange a line. -/
theorem connectable_linked {x y : List Char} {a b : Kant.Rendezvous.Invite} {ca cb : Client}
    (hx : classify x = .invite a) (hy : classify y = .invite b)
    (h : pair x y = .connectable)
    (hra : ca.reach.configured = a.relay) (hrb : cb.reach.configured = b.relay)
    (hua : ca.reach.configuredUp = true) (hub : cb.reach.configuredUp = true)
    (hja : ca.room = a.room) (hjb : cb.room = b.room) :
    Linked ca cb := by
  obtain ⟨a', b', hx', hy', hroom, hne, heq⟩ := (pair_connectable_iff x y).1 h
  rw [hx] at hx'; rw [hy] at hy'
  cases hx'; cases hy'
  refine configured_relay_links (R := a.relay) ?_ ?_ hne hra (by rw [hrb, heq]) hua hub
  · rw [hja, hjb, hroom]
  · rw [hja]; exact invite_room_ne_nil a

/-! ## What the debugger prints -/

/-- The sentence printed for each outcome. -/
def explain : Pairing → List Char
  | .connectable =>
      "connectable: two invitations, one room, one relay - these two meet".toList
  | .sameCode =>
      ("same-code: both pastes are the same code, so there are not two things here to " ++
        "connect; ask the other side for their own invite").toList
  | .notInvites =>
      ("not-invites: this is a share card or a page link - it names a page, never a room; " ++
        "connecting needs a kzinvite code from the share screen").toList
  | .oneNotInvite =>
      ("one-not-invite: only one of these is an invitation; the other names a page, " ++
        "so there is nothing for it to join").toList
  | .differentRooms =>
      ("different-rooms: two invitations, but to two different rooms; both sides must use " ++
        "the same invite").toList
  | .noMeetingPoint =>
      ("no-meeting-point: the invitations agree on the room but name no relay, or two " ++
        "different ones; set `relay =` in kant.config and re-share").toList

/-- The debugger always says something. -/
theorem explain_ne_nil (p : Pairing) : explain p ≠ [] := by
  cases p <;> simp [explain]

set_option maxRecDepth 100000 in
set_option maxHeartbeats 1000000 in
/-- **Six outcomes, six different sentences.** -/
theorem explain_injective {u v : Pairing} (h : explain u = explain v) : u = v := by
  cases u <;> cases v <;> first | rfl | (exfalso; exact absurd h (by decide))

/-! ## Warnings a card can still earn

A card cannot connect, but it can still be wrong in ways worth saying out
loud. -/

/-- Something worth saying about a card even though it is not a
connection. -/
inductive Warning where
  /-- `picture = ./kant-logo.svg` only resolves next to the page; pasted
  anywhere else the picture is missing. -/
  | relativePicture : Warning
  /-- The card's URL does not start with the configured origin, so it
  points at a different deployment. -/
  | foreignOrigin : Warning
deriving DecidableEq, Repr

/-- A picture reference that only works next to the page. -/
def relative (p : List Char) : Bool :=
  !p.isEmpty && !(("http://".toList).isPrefixOf p || ("https://".toList).isPrefixOf p ||
    ("data:".toList).isPrefixOf p)

/-- What is worth saying about this card, given the configured origin. -/
def cardWarnings (origin : List Char) (k : Kant.SiteCard.Card) : List Warning :=
  (if relative k.picture then [Warning.relativePicture] else []) ++
  (if origin.isPrefixOf k.url then [] else [Warning.foreignOrigin])

/-- A card whose picture is a full URL and whose link is on this
deployment earns no warning. -/
theorem cardWarnings_nil {origin : List Char} {k : Kant.SiteCard.Card}
    (hp : relative k.picture = false) (ho : origin.isPrefixOf k.url = true) :
    cardWarnings origin k = [] := by
  simp [cardWarnings, hp, ho]

/-! ## The report, run through the classifier

The two blocks quoted in the report are byte-identical, and this is what
they are. -/

/-- The card as pasted, with the caption line, the link line and the
machine-readable line, exactly as it was reported. -/
def userCardText : List Char :=
  ("kant-zk-pastebin\n" ++
   "https://kant.cicada71.net/#ff810f291f187b808a0183f83c0466874573ef5c4c6d7d9ed430c6f7d710f605\n" ++
   "6b7a63617264:68747470733a2f2f6b616e742e63696361646137312e6e65742f236666383130663" ++
   "23931663138376238303861303138336638336330343636383734353733656635633463366437643" ++
   "96564343330633666376437313066363035:6b616e742d7a6b2d706173746562696e:2e2f6b616e7" ++
   "42d6c6f676f2e737667:746865204b616e7420706173746562696e206c6f676f").toList

/-- The card those characters carry. -/
def userCard : Kant.SiteCard.Card :=
  ⟨"https://kant.cicada71.net/#ff810f291f187b808a0183f83c0466874573ef5c4c6d7d9ed430c6f7d710f605".toList,
   "kant-zk-pastebin".toList,
   "./kant-logo.svg".toList,
   "the Kant pastebin logo".toList⟩

set_option maxRecDepth 40000 in
/-- **What was pasted is a share card** — a page, a caption and a
picture. -/
theorem userCard_classify : classify userCardText = .card userCard := by decide

/-- **It names no room**, so nothing in it can connect to anything. -/
theorem userCard_no_room : roomOf? (classify userCardText) = none := by
  rw [userCard_classify]; rfl

/-- **Both blocks in the report are the same card**, so the verdict is
`sameCode`: there is one object here, not two endpoints. -/
theorem userCard_pair : pair userCardText userCardText = .sameCode :=
  pair_same_card userCard_classify userCard_classify

/-- **And so they provably cannot connect.** -/
theorem userCard_not_connectable : pair userCardText userCardText ≠ .connectable :=
  pair_not_connectable_of_card_left userCard_classify

/-- The one thing that *is* wrong with the card itself: its picture is a
relative reference, so away from the site the logo does not load. -/
theorem userCard_warnings :
    cardWarnings "https://kant.cicada71.net/".toList userCard = [Warning.relativePicture] := by
  decide

/-- The bare page link from the same report. -/
def userPageLink : List Char :=
  "https://kant.cicada71.net/#ff810f291f187b808a0183f83c0466874573ef5c4c6d7d9ed430c6f7d710f605".toList

set_option maxRecDepth 40000 in
/-- **The link on its own is a page**, not a room either: it is the
address of a paste, and pasting it twice still connects nothing. -/
theorem userPageLink_classify :
    classify userPageLink =
      .page "ff810f291f187b808a0183f83c0466874573ef5c4c6d7d9ed430c6f7d710f605".toList := by
  decide

/-- **Two page links do not connect.** -/
theorem userPageLink_not_connectable : pair userPageLink userPageLink ≠ .connectable :=
  pair_not_connectable_of_page_left userPageLink_classify

/-! ## Golden vectors

The same inputs run through `web/kant-carddebug.mjs` in
`web/carddebug-test.mjs`, so the client and this specification cannot
drift apart. -/

/-- An invitation naming a relay. -/
def vecInviteA : List Char :=
  "6b7a696e76697465:68747470733a2f2f72656c61792e6578616d706c65:7365637265742d6f6e65:706565722d61".toList

/-- Another invitation, same relay, a different secret and so a different room. -/
def vecInviteB : List Char :=
  "6b7a696e76697465:68747470733a2f2f72656c61792e6578616d706c65:7365637265742d74776f:706565722d62".toList

/-- An invitation with no relay in it. -/
def vecInviteNoRelay : List Char :=
  "6b7a696e76697465::7365637265742d6f6e65:706565722d63".toList

/-- An invitation to the same room, but by way of a different relay. -/
def vecInviteOtherRelay : List Char :=
  "6b7a696e76697465:68747470733a2f2f6f746865722e6578616d706c65:7365637265742d6f6e65:706565722d64".toList

#guard pair vecInviteA vecInviteA = Pairing.connectable
#guard pair vecInviteA vecInviteB = Pairing.differentRooms
#guard pair vecInviteNoRelay vecInviteNoRelay = Pairing.noMeetingPoint
#guard pair vecInviteA vecInviteOtherRelay = Pairing.noMeetingPoint
#guard pair userCardText vecInviteA = Pairing.oneNotInvite
#guard pair userCardText userPageLink = Pairing.notInvites
#guard pair userCardText userCardText = Pairing.sameCode
#guard pair userPageLink userPageLink = Pairing.sameCode
#guard classify "hello there".toList = Code.unknown
#guard roomOf? (classify vecInviteA) =
  some "aff4dd0dc912a426f8014bb2870bc8e50c6cdb7039d9f3a86c84b5004f61cdb7".toList
#guard roomOf? (classify vecInviteB) =
  some "8885040e43bcf5dc594b34b2beb87fef21d2826fb4c4344e1d0f5e0021f39801".toList
#guard relayOf? (classify vecInviteA) = some "https://relay.example".toList
#guard codeLine "  a  \n  b \n   \n".toList = "b".toList
#guard cardWarnings "https://kant.cicada71.net/".toList userCard = [Warning.relativePicture]

end Kant.CardDebug
