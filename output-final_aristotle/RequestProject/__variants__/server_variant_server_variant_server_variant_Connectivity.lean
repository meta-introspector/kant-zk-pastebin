/-
# Why two clients on one machine would not connect

Two browsers on *one machine* were failing to find each other, and the
client said nothing about why.  This module specifies the decision the
client makes about where to meet, the fix, and the verdict the
diagnostics page prints.

`Reachability` records what the client actually knows: the relay named in
`kant.config`, whether it answered, the page's own origin, and whether
*that* origin answered `/health` as a relay.  `effectiveRelay` is the
decision:

* `effectiveRelay_configured` — a configured relay always wins;
* `effectiveRelay_selfHosted` — with nothing configured, a page served by
  a relay uses that relay.  This is the fix: `node server/relay.mjs
  --static web` now joins two browsers on one machine with no
  configuration at all;
* `effectiveRelay_needs_probe` — and never otherwise, so the older bug
  (pointing the relay at a static origin that has no relay in it) cannot
  come back.

`Linked` says when two clients can exchange a line, and `diagnose` turns
the same facts into a verdict with a sentence attached:

* `two_browsers_one_machine_linked` — the case the user hit, now working;
* `two_browsers_one_machine_stuck` — the same case *without* the fix,
  proved to fail, which is what the old build did;
* `diagnose_eq_ok_iff` — the verdict is `ok` exactly when the two really
  are linked, so the page cannot claim a connection it does not have;
* `diagnose_two_browsers_no_relay`, `diagnose_relayDown`,
  `diagnose_roomMismatch`, `diagnose_noRoom` — each failure gets its own
  verdict, and `explain_injective` shows each verdict its own sentence:
  never silence, and never the same words for two different problems.
-/
import Mathlib
import RequestProject.Kant.Bytes
import RequestProject.Kant.Text

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.Connectivity

open Kant Kant.Bytes Kant.Text

/-! ## Where a client can meet other clients -/

/-- What the client knows about where it can meet other clients. -/
structure Reachability where
  /-- The relay named by `relay =` in `kant.config`; empty when blank. -/
  configured : List Char
  /-- Did the configured relay answer `/health`? -/
  configuredUp : Bool
  /-- The origin this page was served from. -/
  origin : List Char
  /-- Did *that* origin answer `/health` as a relay?  `node
  server/relay.mjs --static web` does; a plain static host does not. -/
  originIsRelay : Bool
deriving DecidableEq, Repr

/-- **The decision.**  A configured relay wins; failing that, the page's
own origin is used, but only if it was probed and really is a relay. -/
def effectiveRelay (r : Reachability) : List Char :=
  if r.configured ≠ [] then r.configured
  else if r.originIsRelay then r.origin else []

/-- A configured relay is always the one used. -/
theorem effectiveRelay_configured {r : Reachability} (h : r.configured ≠ []) :
    effectiveRelay r = r.configured := by simp [effectiveRelay, h]

/-- **The same-machine fix.**  Nothing configured, page served by a relay:
that relay is used. -/
theorem effectiveRelay_selfHosted {r : Reachability} (h : r.configured = [])
    (ho : r.originIsRelay = true) : effectiveRelay r = r.origin := by
  simp [effectiveRelay, h, ho]

/-- **And never otherwise.**  An origin that was not probed, or that is
not a relay, is never used as one. -/
theorem effectiveRelay_needs_probe {r : Reachability} (h : r.configured = [])
    (ho : r.originIsRelay = false) : effectiveRelay r = [] := by
  simp [effectiveRelay, h, ho]

/-- Is there a relay this client can actually use? -/
def RelayUsable (r : Reachability) : Prop :=
  if r.configured = [] then r.originIsRelay = true else r.configuredUp = true

instance (r : Reachability) : Decidable (RelayUsable r) := by
  unfold RelayUsable; split <;> infer_instance

/-! ## Two clients -/

/-- One client as the diagnostics see it. -/
structure Client where
  /-- The room it is in, empty when it is in none. -/
  room : List Char
  /-- What it can reach. -/
  reach : Reachability
  /-- Is a same-browser `BroadcastChannel` available? -/
  bus : Bool
  /-- Which browser instance this tab belongs to.  Two tabs of one
  browser share a number; two browsers on one machine do not. -/
  browser : Nat
deriving DecidableEq, Repr

/-- The two clients share a relay both can use. -/
def SharedRelay (a b : Client) : Prop :=
  RelayUsable a.reach ∧ RelayUsable b.reach ∧
    effectiveRelay a.reach ≠ [] ∧ effectiveRelay a.reach = effectiveRelay b.reach

instance (a b : Client) : Decidable (SharedRelay a b) := by
  unfold SharedRelay; infer_instance

/-- The two clients are tabs of one browser, with the local bus available
to both. -/
def SameBrowser (a b : Client) : Prop :=
  a.bus = true ∧ b.bus = true ∧ a.browser = b.browser

instance (a b : Client) : Decidable (SameBrowser a b) := by
  unfold SameBrowser; infer_instance

/-- **Can these two exchange a line?**  Same non-empty room, and either
the same browser (the local bus) or a relay both can use. -/
def Linked (a b : Client) : Prop :=
  a.room = b.room ∧ a.room ≠ [] ∧ (SameBrowser a b ∨ SharedRelay a b)

instance (a b : Client) : Decidable (Linked a b) := by
  unfold Linked; infer_instance

theorem Linked.symm {a b : Client} (h : Linked a b) : Linked b a := by
  obtain ⟨hroom, hne, hcase⟩ := h
  refine ⟨hroom.symm, by rw [← hroom]; exact hne, ?_⟩
  rcases hcase with ⟨ha, hb, hbr⟩ | ⟨ha, hb, hne', heq⟩
  · exact Or.inl ⟨hb, ha, hbr.symm⟩
  · exact Or.inr ⟨hb, ha, by rw [← heq]; exact hne', heq.symm⟩

/-- Two tabs of one browser need no server at all. -/
theorem same_browser_linked {a b : Client} (hroom : a.room = b.room) (hne : a.room ≠ [])
    (ha : a.bus = true) (hb : b.bus = true) (hsame : a.browser = b.browser) :
    Linked a b :=
  ⟨hroom, hne, Or.inl ⟨ha, hb, hsame⟩⟩

/-- **The case that was failing.**  Two *different* browsers on one
machine, both pages served by the same self-hosting relay, both in the
room the invite named: they are linked. -/
theorem two_browsers_one_machine_linked {a b : Client}
    (hroom : a.room = b.room) (hne : a.room ≠ [])
    (hca : a.reach.configured = []) (hcb : b.reach.configured = [])
    (hoa : a.reach.originIsRelay = true) (hob : b.reach.originIsRelay = true)
    (horigin : a.reach.origin = b.reach.origin) (hoe : a.reach.origin ≠ []) :
    Linked a b := by
  have hea : effectiveRelay a.reach = a.reach.origin := effectiveRelay_selfHosted hca hoa
  have heb : effectiveRelay b.reach = b.reach.origin := effectiveRelay_selfHosted hcb hob
  refine ⟨hroom, hne, Or.inr ⟨?_, ?_, ?_, ?_⟩⟩
  · simp [RelayUsable, hca, hoa]
  · simp [RelayUsable, hcb, hob]
  · rw [hea]; exact hoe
  · rw [hea, heb, horigin]

/-- **The same case as it used to behave.**  With no relay configured and
the origin never probed as one, two browsers on one machine cannot
exchange anything, however correct the invite link is. -/
theorem two_browsers_one_machine_stuck {a b : Client}
    (hca : a.reach.configured = []) (hoa : a.reach.originIsRelay = false)
    (hdiff : a.browser ≠ b.browser) : ¬ Linked a b := by
  rintro ⟨-, -, hcase⟩
  rcases hcase with ⟨-, -, hbr⟩ | ⟨-, -, hne, -⟩
  · exact hdiff hbr
  · exact hne (effectiveRelay_needs_probe hca hoa)

/-! ## The verdict -/

/-- What the diagnostics page says. -/
inductive Verdict
  /-- The two really can exchange lines. -/
  | ok
  /-- One of them is not in a room. -/
  | noRoom
  /-- They are in different rooms: the link pasted is not the link shown. -/
  | roomMismatch
  /-- A relay is configured but did not answer. -/
  | relayDown
  /-- Separate browsers with no relay between them — the same-machine
  failure. -/
  | onlyThisBrowser
  /-- No transport at all. -/
  | noTransport
deriving DecidableEq, Repr

/-- A relay was named but is not answering. -/
def RelayDown (c : Client) : Prop :=
  c.reach.configured ≠ [] ∧ c.reach.configuredUp = false

instance (c : Client) : Decidable (RelayDown c) := by unfold RelayDown; infer_instance

/-- Turn the facts into a verdict. -/
def diagnose (a b : Client) : Verdict :=
  if a.room = [] ∨ b.room = [] then .noRoom
  else if a.room ≠ b.room then .roomMismatch
  else if Linked a b then .ok
  else if RelayDown a ∨ RelayDown b then .relayDown
  else if a.bus = true ∧ b.bus = true then .onlyThisBrowser
  else .noTransport

/-- **The page cannot claim a connection it does not have.** -/
theorem diagnose_eq_ok_iff (a b : Client) : diagnose a b = .ok ↔ Linked a b := by
  constructor
  · intro h
    unfold diagnose at h
    split at h
    · exact absurd h (by simp)
    · split at h
      · exact absurd h (by simp)
      · split at h
        · assumption
        · split at h
          · exact absurd h (by simp)
          · split at h <;> exact absurd h (by simp)
  · intro h
    have hroom : a.room = b.room := h.1
    have hne : a.room ≠ [] := h.2.1
    have hb : b.room ≠ [] := by rw [← hroom]; exact hne
    unfold diagnose
    rw [if_neg (by tauto), if_neg (by simpa using hroom), if_pos h]

/-- **Nobody is told "connected" while out of a room.** -/
theorem diagnose_noRoom {a b : Client} (h : a.room = [] ∨ b.room = []) :
    diagnose a b = .noRoom := by
  unfold diagnose; rw [if_pos h]

/-- **A joiner who landed in the wrong room is told so.** -/
theorem diagnose_roomMismatch {a b : Client} (ha : a.room ≠ []) (hb : b.room ≠ [])
    (h : a.room ≠ b.room) : diagnose a b = .roomMismatch := by
  unfold diagnose
  rw [if_neg (by tauto), if_pos h]

/-- **A relay that does not answer is named as the problem.**  (Two tabs
of one browser still talk over the local bus, so this is stated for two
separate browsers.) -/
theorem diagnose_relayDown {a b : Client} (hroom : a.room = b.room) (hne : a.room ≠ [])
    (hdown : RelayDown a) (hdiff : a.browser ≠ b.browser) : diagnose a b = .relayDown := by
  have hb : b.room ≠ [] := by rw [← hroom]; exact hne
  have hnl : ¬ Linked a b := by
    rintro ⟨-, -, hcase⟩
    rcases hcase with ⟨-, -, hbr⟩ | ⟨hu, -, -, -⟩
    · exact hdiff hbr
    · simp only [RelayUsable, if_neg hdown.1] at hu
      rw [hdown.2] at hu
      exact Bool.noConfusion hu
  unfold diagnose
  rw [if_neg (by tauto), if_neg (by simpa using hroom), if_neg hnl, if_pos (Or.inl hdown)]

/-- **The same-machine failure gets its own verdict**, not silence: two
browsers, a bus each that cannot reach the other, and no relay between
them. -/
theorem diagnose_two_browsers_no_relay {a b : Client}
    (hroom : a.room = b.room) (hne : a.room ≠ [])
    (hca : a.reach.configured = []) (hcb : b.reach.configured = [])
    (hoa : a.reach.originIsRelay = false)
    (ha : a.bus = true) (hb : b.bus = true) (hdiff : a.browser ≠ b.browser) :
    diagnose a b = .onlyThisBrowser := by
  have hbr : b.room ≠ [] := by rw [← hroom]; exact hne
  have hnl : ¬ Linked a b := two_browsers_one_machine_stuck hca hoa hdiff
  have hnd : ¬ (RelayDown a ∨ RelayDown b) := by
    rintro (⟨h, -⟩ | ⟨h, -⟩)
    · exact h hca
    · exact h hcb
  unfold diagnose
  rw [if_neg (by tauto), if_neg (by simpa using hroom), if_neg hnl, if_neg hnd,
    if_pos ⟨ha, hb⟩]

/-! ## What the page prints -/

/-- The sentence the diagnostics page prints for a verdict. -/
def explain : Verdict → List Char
  | .ok => "ok: you and the other client share a room and a transport".toList
  | .noRoom => "no-room: open a room, or paste an invite link".toList
  | .roomMismatch =>
      "room-mismatch: the link pasted is not the link that was shown".toList
  | .relayDown =>
      "relay-down: the configured relay did not answer; check `relay =` in kant.config".toList
  | .onlyThisBrowser =>
      ("only-this-browser: two separate browsers with no relay between them; serve the page " ++
        "with `node server/relay.mjs --static web`, or set `relay =`").toList
  | .noTransport => "no-transport: no relay, and no same-browser channel".toList

/-- The page always has something to say. -/
theorem explain_ne_nil (v : Verdict) : explain v ≠ [] := by
  cases v <;> simp [explain]

set_option maxRecDepth 100000 in
set_option maxHeartbeats 1000000 in
/-- **Different problems read differently**: the page never says the same
thing about two different verdicts. -/
theorem explain_injective {u v : Verdict} (h : explain u = explain v) : u = v := by
  cases u <;> cases v <;> first | rfl | (exfalso; exact absurd h (by decide))

end Kant.Connectivity
