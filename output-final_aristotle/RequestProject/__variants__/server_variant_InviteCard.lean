/-
# The invite code: the whole link, an icon and a line of text

A chat invitation used to be shown as a bare payload,

```
kzinvite:68747470733a2f2f6b616e742e63696361646137312e6e6574:05a3…3b38:706565722d333861336b
```

which is what a scanner reads out of a code that carries only the
fragment of the link.  A stranger who scans that gets a string of hex
and nothing to open.  This module says what an invite code must carry
instead:

```
https://kant.cicada71.net/#6b7a696e76697465:68747470733a2f2f…:05a3…:706565722d333861336b
```

— the *whole* page URL, its origin taken from `kant.config`
(`Kant.SiteCard.Config`) — and it dresses that code as a **card**: the
icon in the middle of the code and the caption and link printed under
it.

Definitions: `inviteUrl` (the payload of the code), `Dress` (the icon
and the text), `inviteCard`, `inviteCardSvg`.

Proved here:

* `inviteUrl_origin_prefix` — the payload starts with the site, so any
  scanner offers an openable link;
* `inviteUrl_not_bare` and `inviteUrl_length` — the payload is
  *not* the bare `kzinvite:…` envelope the old code showed, as long as
  the deployment has an origin at all;
* `parseInviteUrl_inviteUrl`, `inviteCard_scan_room` — this client still
  reads the exact invitation, and both sides land in the same room;
* `inviteCard_url`, `inviteCardSvg_url_visible` — the code and the text
  under it carry that same whole URL;
* `inviteCardSvg_icon_used`, `inviteCardSvg_caption_visible`,
  `inviteCardSvg_caption_recoverable`, `inviteCard_no_markup` — the
  custom icon and the custom text really appear on the card, and neither
  can break out of its element;
* `inviteCard_icon_area_bound` — the icon covers at most a
  twenty-fifth of the code's modules, inside the error-correction
  budget, so the code still scans;
* `readCard_inviteCardSvg` and `inviteCardSvg_roundTrip` — the exported
  picture reads back as the same card, and its URL still parses to the
  invitation that was shared;
* `inviteUrl_fits_qr` — the dressed link still fits in one code.
-/
import Mathlib
import RequestProject.Kant.Bytes
import RequestProject.Kant.Text
import RequestProject.Kant.Erdfa
import RequestProject.Kant.Clipboard
import RequestProject.Kant.Rendezvous
import RequestProject.Kant.Sneakernet
import RequestProject.Kant.SiteCard

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.InviteCard

open Kant Kant.Bytes Kant.Text Kant.Clipboard Kant.Rendezvous Kant.SiteCard

/-! ## The payload of an invite code -/

/-- **What an invite code carries: the whole page URL.**  The configured
origin, the fragment marker, and the invitation itself. -/
def inviteUrl (c : Config) (i : Invite) : List Char :=
  Kant.SiteCard.shareUrl c (ofInvite i)

theorem inviteUrl_eq (c : Config) (i : Invite) :
    inviteUrl c i = c.origin ++ Kant.Clipboard.hash :: copyInvite i := rfl

/-- The payload begins with the site: a scanner that knows nothing about
this program is still offered a link it can open. -/
theorem inviteUrl_origin_prefix (c : Config) (i : Invite) : c.origin <+: inviteUrl c i :=
  ⟨_, rfl⟩

/-- **The code no longer carries the bare payload.**  Whatever follows
the origin is the fragment, so a deployment with an origin shows a link,
never `kzinvite:…` on its own. -/
theorem inviteUrl_not_bare {c : Config} (h : c.origin ≠ []) (i : Invite) :
    inviteUrl c i ≠ copyInvite i := by
  intro heq
  have hlen := congrArg List.length heq
  rw [inviteUrl_eq] at hlen
  simp only [List.length_append, List.length_cons] at hlen
  have : c.origin.length = 0 := by omega
  exact h (List.eq_nil_of_length_eq_zero this)

/-- The payload is exactly the origin, a `'#'` and the invitation: an
origin of even one character makes the code longer than the bare
envelope the old code showed. -/
theorem inviteUrl_length (c : Config) (i : Invite) :
    (inviteUrl c i).length = c.origin.length + (copyInvite i).length + 1 := by
  rw [inviteUrl_eq]
  simp only [List.length_append, List.length_cons]
  omega

/-- Read an invitation out of a scanned code. -/
def parseInviteUrl (u : List Char) : Option Invite := Kant.Rendezvous.parseInviteUrl u

/-- **Scanning the code recovers exactly the invitation.** -/
theorem parseInviteUrl_inviteUrl {c : Config} (hc : c.Wf) {i : Invite} (h : i.Wire) :
    parseInviteUrl (inviteUrl c i) = some i :=
  Kant.Rendezvous.parseInviteUrl_inviteUrl hc.noHash h

/-- An invite URL is ASCII, so it survives any channel. -/
theorem isAscii_inviteUrl {c : Config} (hc : c.Wf) (i : Invite) : IsAscii (inviteUrl c i) := by
  intro ch hch
  rw [inviteUrl_eq] at hch
  simp only [List.mem_append, List.mem_cons] at hch
  rcases hch with hch | rfl | hch
  · exact hc.ascii ch hch
  · decide
  · exact isAscii_copyInvite i ch hch

/-! ## The dressing: a custom icon and a custom line of text -/

/-- How an invite code is dressed: the picture drawn in the middle of
the code, the line of text printed under it, and the picture's
description. -/
structure Dress where
  /-- The line of text printed under the code. -/
  caption : List Char
  /-- The picture drawn in the middle of the code. -/
  icon : List Char
  /-- The picture's text description. -/
  alt : List Char
deriving DecidableEq, Repr

/-- The dressing is transmissible when its text is ASCII. -/
structure Dress.Wf (d : Dress) : Prop where
  /-- The caption is ASCII. -/
  caption : IsAscii d.caption
  /-- The picture reference is ASCII. -/
  icon : IsAscii d.icon
  /-- The description is ASCII. -/
  alt : IsAscii d.alt

/-- The dressing named by the deployment's configuration file. -/
def ofConfig (c : Config) : Dress := ⟨c.caption, c.picture, c.alt⟩

/-- **The invite card**: the whole invite URL, with a custom icon and a
custom line of text. -/
def inviteCard (c : Config) (d : Dress) (i : Invite) : Card :=
  ⟨inviteUrl c i, d.caption, d.icon, d.alt⟩

@[simp] theorem inviteCard_url (c : Config) (d : Dress) (i : Invite) :
    (inviteCard c d i).url = inviteUrl c i := rfl

@[simp] theorem inviteCard_caption (c : Config) (d : Dress) (i : Invite) :
    (inviteCard c d i).caption = d.caption := rfl

@[simp] theorem inviteCard_picture (c : Config) (d : Dress) (i : Invite) :
    (inviteCard c d i).picture = d.icon := rfl

theorem inviteCard_wf {c : Config} (hc : c.Wf) {d : Dress} (hd : d.Wf) (i : Invite) :
    (inviteCard c d i).Wf :=
  ⟨isAscii_inviteUrl hc i, hd.caption, hd.icon, hd.alt⟩

/-- The card as one SVG document: the machine-readable card, then the
code with the icon in the middle and the caption and link under it. -/
def inviteCardSvg (c : Config) (d : Dress) (i : Invite) (modules : List (List Bool))
    (scale border : Nat) : List Char :=
  cardSvg (inviteCard c d i) modules scale border

/-! ## What the card shows -/

/-- **The custom icon really is drawn on the code.** -/
theorem inviteCardSvg_icon_used (c : Config) (d : Dress) (i : Invite)
    (modules : List (List Bool)) (scale border : Nat) :
    Kant.Erdfa.escape d.icon <:+: inviteCardSvg c d i modules scale border :=
  cardSvg_picture_used (inviteCard c d i) modules scale border

/-- **The custom text really is printed under the code.** -/
theorem inviteCardSvg_caption_visible (c : Config) (d : Dress) (i : Invite)
    (modules : List (List Bool)) (scale border : Nat) :
    Kant.Erdfa.escape d.caption <:+: inviteCardSvg c d i modules scale border :=
  cardSvg_caption_visible (inviteCard c d i) modules scale border

/-- **The whole invite link is printed on the card**, so somebody who
cannot scan can still type it in. -/
theorem inviteCardSvg_url_visible (c : Config) (d : Dress) (i : Invite)
    (modules : List (List Bool)) (scale border : Nat) :
    Kant.Erdfa.escape (inviteUrl c i) <:+: inviteCardSvg c d i modules scale border :=
  cardSvg_url_visible (inviteCard c d i) modules scale border

/-- The caption a reader sees is the caption that was chosen. -/
theorem inviteCardSvg_caption_recoverable (d : Dress) :
    Kant.Erdfa.unescape (Kant.Erdfa.escape d.caption) = d.caption :=
  Kant.Erdfa.escape_unescape_id _

/-- **No icon reference and no caption can break out of its element**,
whatever the user types. -/
theorem inviteCard_no_markup (c : Config) (d : Dress) (i : Invite) :
    ('<' ∉ Kant.Erdfa.escape d.caption ∧ '>' ∉ Kant.Erdfa.escape d.caption ∧
        '"' ∉ Kant.Erdfa.escape d.caption) ∧
    ('<' ∉ Kant.Erdfa.escape d.icon ∧ '>' ∉ Kant.Erdfa.escape d.icon ∧
        '"' ∉ Kant.Erdfa.escape d.icon) ∧
    ('<' ∉ Kant.Erdfa.escape (inviteUrl c i) ∧ '>' ∉ Kant.Erdfa.escape (inviteUrl c i) ∧
        '"' ∉ Kant.Erdfa.escape (inviteUrl c i)) :=
  ⟨Kant.Erdfa.escape_no_markup _, Kant.Erdfa.escape_no_markup _, Kant.Erdfa.escape_no_markup _⟩

/-- **The icon never eats more than a twenty-fifth of the code**, so the
error correction still carries the code past it. -/
theorem inviteCard_icon_area_bound (n : Nat) : 25 * (logoSide n * logoSide n) ≤ n * n :=
  logo_area_bound n

/-! ## The card reads back -/

/-- **The exported picture still carries the card.** -/
theorem readCard_inviteCardSvg {c : Config} (hc : c.Wf) {d : Dress} (hd : d.Wf) (i : Invite)
    (modules : List (List Bool)) (scale border : Nat) :
    readCard (inviteCardSvg c d i modules scale border) = some (inviteCard c d i) :=
  readCard_cardSvg (inviteCard_wf hc hd i) modules scale border

/-- **End to end.**  Export the invite card, read it back, scan the URL
it carries: what comes out is the invitation that was shared — not a
bare payload, but the whole page link. -/
theorem inviteCardSvg_roundTrip {c : Config} (hc : c.Wf) {d : Dress} (hd : d.Wf)
    {i : Invite} (hi : i.Wire) (modules : List (List Bool)) (scale border : Nat) :
    ((readCard (inviteCardSvg c d i modules scale border)).map Card.url).bind parseInviteUrl
      = some i := by
  rw [readCard_inviteCardSvg hc hd i]
  simpa using parseInviteUrl_inviteUrl hc hi

/-- **Both sides land in the same room**, the scanner reading the room
out of the link the card shows. -/
theorem inviteCard_scan_room {c : Config} (hc : c.Wf) {d : Dress} {i j : Invite} (hi : i.Wire)
    (hj : parseInviteUrl (inviteCard c d i).url = some j) : j.room = i.room := by
  rw [inviteCard_url, parseInviteUrl_inviteUrl hc hi] at hj
  rw [Option.some.injEq] at hj
  rw [hj]

/-- The card shared as plain text: the caption a human reads, the whole
link, then the machine-readable line. -/
def inviteChatText (c : Config) (d : Dress) (i : Invite) : List Char :=
  chatText (inviteCard c d i)

/-- **An invite card pasted into any chat window comes back whole.** -/
theorem readChatText_inviteChatText {c : Config} (hc : c.Wf) {d : Dress} (hd : d.Wf)
    (i : Invite) (hcap : '\n' ∉ d.caption) :
    readChatText (inviteChatText c d i) = some (inviteCard c d i) := by
  refine readChatText_chatText (inviteCard_wf hc hd i) hcap ?_
  intro hmem
  rw [inviteCard_url, inviteUrl_eq] at hmem
  simp only [List.mem_append, List.mem_cons] at hmem
  rcases hmem with hmem | hmem | hmem
  · exact hc.origin.oneLine hmem
  · exact absurd hmem (by decide)
  · exact Kant.SiteCard.newline_not_mem_encode (ofInvite i) hmem

/-! ## Size -/

/-- **A dressed invite link still fits in one code.**  The origin, the
`'#'` and the invitation together stay inside the binary capacity of a
version-40 QR code. -/
theorem inviteUrl_fits_qr {c : Config} {i : Invite} (ho : c.origin.length ≤ 500)
    (hsum : (((ofInvite i).fields).map List.length).sum ≤ 1100)
    (hn : ((ofInvite i).fields).length ≤ 100) :
    (inviteUrl c i).length ≤ Kant.Sneakernet.Channel.qr.capacity := by
  have h := Envelope.encode_length_le (ofInvite i)
  have htag : (ofInvite i).tag.length = 8 := rfl
  have hcap : Kant.Sneakernet.Channel.qr.capacity = 2953 := rfl
  rw [inviteUrl_eq]
  simp only [List.length_append, List.length_cons, copyInvite, htag] at h ⊢
  omega

end Kant.InviteCard
