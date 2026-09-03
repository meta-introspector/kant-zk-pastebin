/-
# Serving credits

A node earns credit for bytes it serves to others and spends credit to
have its own pastes pinned by the network.  The ledger is append-only:
an earn log and a spend log, both keyed by peer.

Proved here:

* `serve_balance` — serving `n` bytes credits exactly `creditsFor n` and
  touches no other peer's balance (`serve_balance_of_ne`);
* `serve_valid`, `spend_valid` — the ledger invariant *spent ≤ earned* is
  preserved, so no account can be driven negative;
* `spend_eq_none_iff` — a spend is refused exactly when it would
  overdraw, and a successful spend debits exactly the amount asked
  (`spend_balance`);
* `totalEarned_serve` — credit is created only by serving, one unit per
  kibibyte, so the total in circulation is the total service performed.
-/
import Mathlib

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.Credits

/-- A peer identity (a libp2p peer id, an iroh node id, …). -/
abbrev Peer := List Char

/-- Credits earned by `p` in a log. -/
def earned (log : List (Peer × Nat)) (p : Peer) : Nat :=
  ((log.filter (fun e => e.1 == p)).map Prod.snd).sum

/-- Total credits recorded in a log. -/
def total (log : List (Peer × Nat)) : Nat := (log.map Prod.snd).sum

/-- One credit per kibibyte served. -/
def creditsFor (bytes : Nat) : Nat := bytes / 1024

/-- The append-only credit ledger. -/
structure Ledger where
  earnLog : List (Peer × Nat) := []
  spendLog : List (Peer × Nat) := []
deriving Repr

namespace Ledger

/-- The empty ledger. -/
def empty : Ledger := {}

/-- A peer's balance. -/
def balance (L : Ledger) (p : Peer) : Nat := earned L.earnLog p - earned L.spendLog p

/-- No peer has spent more than it earned. -/
def valid (L : Ledger) : Prop := ∀ p, earned L.spendLog p ≤ earned L.earnLog p

@[simp] theorem earned_nil (p : Peer) : earned [] p = 0 := rfl

@[simp] theorem earned_cons_self (p : Peer) (n : Nat) (log : List (Peer × Nat)) :
    earned ((p, n) :: log) p = n + earned log p := by
  simp [earned]

@[simp] theorem earned_cons_of_ne {p q : Peer} (h : q ≠ p) (n : Nat)
    (log : List (Peer × Nat)) : earned ((q, n) :: log) p = earned log p := by
  simp [earned, h]

@[simp] theorem total_cons (p : Peer) (n : Nat) (log : List (Peer × Nat)) :
    total ((p, n) :: log) = n + total log := by
  simp [total]

/-- Record a service: `p` served `bytes` bytes to somebody. -/
def serve (L : Ledger) (p : Peer) (bytes : Nat) : Ledger :=
  { L with earnLog := (p, creditsFor bytes) :: L.earnLog }

/-- Spend credit, refusing to overdraw. -/
def spend (L : Ledger) (p : Peer) (c : Nat) : Option Ledger :=
  if c ≤ L.balance p then some { L with spendLog := (p, c) :: L.spendLog } else none

@[simp] theorem empty_valid : empty.valid := by
  intro p; simp [empty]

@[simp] theorem balance_empty (p : Peer) : empty.balance p = 0 := rfl

/-- Serving credits exactly `creditsFor bytes`. -/
theorem serve_balance {L : Ledger} (hL : L.valid) (p : Peer) (bytes : Nat) :
    (L.serve p bytes).balance p = L.balance p + creditsFor bytes := by
  have h := hL p
  simp only [serve, balance, earned_cons_self]
  omega

/-- Serving never touches another peer's balance. -/
theorem serve_balance_of_ne (L : Ledger) {p q : Peer} (h : q ≠ p) (bytes : Nat) :
    (L.serve q bytes).balance p = L.balance p := by
  simp [serve, balance, earned_cons_of_ne h]

/-- Serving preserves the ledger invariant. -/
theorem serve_valid {L : Ledger} (hL : L.valid) (p : Peer) (bytes : Nat) :
    (L.serve p bytes).valid := by
  intro q
  by_cases h : q = p
  · subst h
    have := hL q
    simp only [serve, earned_cons_self]
    omega
  · simpa [serve, earned_cons_of_ne (Ne.symm h)] using hL q

/-- A spend is refused exactly when it would overdraw the account. -/
theorem spend_eq_none_iff (L : Ledger) (p : Peer) (c : Nat) :
    L.spend p c = none ↔ L.balance p < c := by
  unfold spend
  by_cases h : c ≤ L.balance p
  · rw [if_pos h]; simp only [reduceCtorEq, false_iff, Nat.not_lt]; exact h
  · rw [if_neg h]; simp only [true_iff]; omega

/-- A successful spend debits exactly the amount requested. -/
theorem spend_balance {L : Ledger} {p : Peer} {c : Nat} {L' : Ledger}
    (h : L.spend p c = some L') : L'.balance p = L.balance p - c := by
  unfold spend at h
  by_cases hc : c ≤ L.balance p
  · rw [if_pos hc] at h
    obtain rfl := Option.some.inj h
    simp only [balance, earned_cons_self]
    have hbal : L.balance p = earned L.earnLog p - earned L.spendLog p := rfl
    omega
  · rw [if_neg hc] at h
    exact absurd h (by simp)

/-- Another peer's balance is unaffected by a spend. -/
theorem spend_balance_of_ne {L : Ledger} {p q : Peer} {c : Nat} {L' : Ledger}
    (hne : q ≠ p) (h : L.spend q c = some L') : L'.balance p = L.balance p := by
  unfold spend at h
  by_cases hc : c ≤ L.balance q
  · rw [if_pos hc] at h
    obtain rfl := Option.some.inj h
    simp [balance, earned_cons_of_ne hne]
  · rw [if_neg hc] at h
    exact absurd h (by simp)

/-- Spending preserves the ledger invariant: no account goes negative. -/
theorem spend_valid {L : Ledger} (hL : L.valid) {p : Peer} {c : Nat} {L' : Ledger}
    (h : L.spend p c = some L') : L'.valid := by
  unfold spend at h
  by_cases hc : c ≤ L.balance p
  · rw [if_pos hc] at h
    obtain rfl := Option.some.inj h
    intro q
    by_cases hq : q = p
    · subst hq
      have hbal : L.balance q = earned L.earnLog q - earned L.spendLog q := rfl
      have := hL q
      simp only [earned_cons_self]
      omega
    · simpa [earned_cons_of_ne (Ne.symm hq)] using hL q
  · rw [if_neg hc] at h
    exact absurd h (by simp)

/-- Total credit in circulation. -/
def totalEarned (L : Ledger) : Nat := total L.earnLog

/-- Credit is created only by serving, at one unit per kibibyte. -/
theorem totalEarned_serve (L : Ledger) (p : Peer) (bytes : Nat) :
    (L.serve p bytes).totalEarned = L.totalEarned + creditsFor bytes := by
  simp [totalEarned, serve, Nat.add_comm]

/-- Serving less than a kibibyte earns nothing; serving a whole number of
kibibytes earns exactly that many credits. -/
theorem creditsFor_kib (k : Nat) : creditsFor (1024 * k) = k := by
  simp [creditsFor]

theorem creditsFor_lt (b : Nat) (h : b < 1024) : creditsFor b = 0 := by
  simp [creditsFor, Nat.div_eq_of_lt h]

/-- A peer can never have earned more than the whole network paid out. -/
theorem earned_le_total (log : List (Peer × Nat)) (p : Peer) : earned log p ≤ total log := by
  induction log with
  | nil => simp [earned, total]
  | cons e log ih =>
      obtain ⟨q, n⟩ := e
      by_cases h : q = p
      · subst h
        rw [earned_cons_self, total_cons]
        omega
      · rw [earned_cons_of_ne h, total_cons]
        omega

/-- Balances never exceed the credit ever created. -/
theorem balance_le_totalEarned (L : Ledger) (p : Peer) : L.balance p ≤ L.totalEarned := by
  have h := earned_le_total L.earnLog p
  have hb : L.balance p ≤ earned L.earnLog p := Nat.sub_le _ _
  unfold totalEarned
  omega

end Ledger

end Kant.Credits
