/-
# Pastes and the content-addressed block store
Lean 4 port of `src/paste.rs`, `src/model.rs` and `src/storage.rs`.

A paste is content addressed: its *witness* is the hex digest of its
content and its *CID* is the DASL address of that content.  The store
(the UUCP spool / IPFS flatfs / Kafka mirror of `storage.rs`) is a
grow-only map from witness to paste.

Proved here:

* every paste retrieved under a witness really has that witness
  (`Store.get_witness`) — the store cannot serve content under a wrong
  address;
* `put` then `get` returns the paste (`Store.get_put_eq`);
* `put` is idempotent (`Store.put_idem`), which is what makes re-pinning
  or re-receiving the same block from IPFS/torrent a no-op;
* `put` never loses data (`Store.get_put_of_ne`, `Store.has_put_mono`);
* puts of pastes with different witnesses commute observationally
  (`Store.put_comm_lookup`) — the store is a join-semilattice, the fact
  the peer-to-peer sync layer needs.
-/
import Mathlib
import RequestProject.Kant.Bytes
import RequestProject.Kant.Dasl
import RequestProject.Kant.Erdfa

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant

open Kant.Bytes Kant.Dasl

/-- A paste, as in `model.rs`/`paste.rs`. -/
structure Paste where
  /-- Human-facing identifier (`paste_<timestamp>` upstream). -/
  id : List Char
  /-- Optional title. -/
  title : List Char
  /-- Raw content bytes. -/
  content : Blob
  /-- Timestamp string. -/
  timestamp : List Char
  /-- Threading: the paste this one replies to / forks. -/
  replyTo : Option (List Char) := none
deriving DecidableEq, Repr

namespace Paste

/-- The SHA-256-shaped witness of `Paste::new`: hex of the content digest. -/
def witness (p : Paste) : List Char := Kant.Bytes.witness p.content

/-- The DASL content address of the paste. -/
def cid (p : Paste) : Nat := nestedCid p.content

/-- The orbifold coordinates used for navigation/sharding
(`to_monster_coords`). -/
def coords (p : Paste) : Orbifold := orbifoldCoords p.content

/-- Monster coordinates always land in `Z/71 × Z/59 × Z/47`. -/
theorem coords_valid (p : Paste) : (p.coords).valid := orbifoldCoords_valid _

/-- The witness is always 64 hex characters (`test_paste_creation`). -/
@[simp] theorem witness_length (p : Paste) : p.witness.length = 64 :=
  Kant.Bytes.witness_length _

/-- The address of a paste depends only on its content. -/
theorem cid_congr {p q : Paste} (h : p.content = q.content) : p.cid = q.cid := by
  simp [cid, h]

/-- The escaped title embedded into the eRDFa/HTML rendering. -/
def escapedTitle (p : Paste) : List Char := Kant.Erdfa.escape p.title

/-- A reader can always recover the title from the rendering. -/
theorem escapedTitle_recoverable (p : Paste) :
    Kant.Erdfa.unescape p.escapedTitle = p.title :=
  Kant.Erdfa.escape_unescape_id _

end Paste

/-! ## The content-addressed store -/

/-- The block store: a list of pastes, looked up by witness.  This models
the UUCP spool, the IPFS flatfs block directory and the Kafka mirror
uniformly — all three are keyed by the content digest. -/
structure Store where
  entries : List Paste
deriving Repr

namespace Store

/-- The empty store. -/
def empty : Store := ⟨[]⟩

/-- `load_content`: fetch a paste by its witness. -/
def get (st : Store) (w : List Char) : Option Paste :=
  st.entries.find? (fun p => p.witness == w)

/-- `save_content`: store a paste, keyed by its own witness.  Storing a
block that is already present is a no-op, exactly as writing an existing
block to flatfs is. -/
def put (st : Store) (p : Paste) : Store :=
  if (st.get p.witness).isSome then st else ⟨p :: st.entries⟩

/-- Does the store answer to this witness? -/
def has (st : Store) (w : List Char) : Bool := (st.get w).isSome

@[simp] theorem get_empty (w : List Char) : empty.get w = none := rfl

/-- Lookup in a cons-store. -/
theorem get_cons (p : Paste) (es : List Paste) (w : List Char) :
    Store.get ⟨p :: es⟩ w = if p.witness = w then some p else Store.get ⟨es⟩ w := by
  simp only [Store.get, List.find?_cons]
  cases h : (p.witness == w) with
  | true => simp_all
  | false => simp_all

/-- Anything the store returns for a witness really carries that witness:
content addressing is honest. -/
theorem get_witness {st : Store} {w : List Char} {p : Paste} (h : st.get w = some p) :
    p.witness = w := by
  have h' := List.find?_some h
  simpa using h'

theorem put_new {st : Store} {p : Paste} (h : ¬ (st.get p.witness).isSome) :
    st.put p = ⟨p :: st.entries⟩ := if_neg h

theorem put_old {st : Store} {p : Paste} (h : (st.get p.witness).isSome) :
    st.put p = st := if_pos h

/-- Retrieval after a fresh store returns exactly the stored paste. -/
theorem get_put_eq {st : Store} {p : Paste} (h : ¬ (st.get p.witness).isSome) :
    (st.put p).get p.witness = some p := by
  rw [put_new h, get_cons, if_pos rfl]

/-- After storing a paste, its witness always resolves. -/
theorem get_put_self (st : Store) (p : Paste) : ((st.put p).get p.witness).isSome := by
  by_cases h : (st.get p.witness).isSome
  · rw [put_old h]; exact h
  · rw [get_put_eq h]; rfl

/-- Storing is idempotent: re-receiving a block from another peer, or
re-pinning it, changes nothing. -/
theorem put_idem (st : Store) (p : Paste) : (st.put p).put p = st.put p :=
  put_old (get_put_self st p)

/-- Storing never loses data. -/
theorem get_put_of_ne {st : Store} {p : Paste} {w : List Char} {q : Paste}
    (h : st.get w = some q) : (st.put p).get w = some q := by
  by_cases hp : (st.get p.witness).isSome
  · rw [put_old hp]; exact h
  · have hw : p.witness ≠ w := by
      intro hw; subst hw; rw [h] at hp; exact hp rfl
    rw [put_new hp, get_cons, if_neg hw]
    exact h

/-- Storing only ever adds witnesses (monotone growth). -/
theorem has_put_mono {st : Store} {p : Paste} {w : List Char} (h : st.has w) :
    (st.put p).has w := by
  unfold has at h ⊢
  rcases hopt : st.get w with _ | q
  · rw [hopt] at h; exact absurd h (by simp)
  · rw [get_put_of_ne hopt]; rfl

/-- The witnesses a store answers to. -/
def witnesses (st : Store) : List (List Char) := st.entries.map Paste.witness

/-- Two pastes with different witnesses can be stored in either order and
the resulting stores are observationally equal: `put` is a commutative
join, so peers that receive blocks in different orders agree. -/
theorem put_comm_lookup (st : Store) (p q : Paste) (hpq : p.witness ≠ q.witness)
    (hp : ¬ (st.get p.witness).isSome) (hq : ¬ (st.get q.witness).isSome) (w : List Char) :
    ((st.put p).put q).get w = ((st.put q).put p).get w := by
  have hq' : ¬ ((st.put p).get q.witness).isSome := by
    rw [put_new hp, get_cons, if_neg hpq]; exact hq
  have hp' : ¬ ((st.put q).get p.witness).isSome := by
    rw [put_new hq, get_cons, if_neg (Ne.symm hpq)]; exact hp
  rw [put_new hq', put_new hp', put_new hp, put_new hq, get_cons, get_cons, get_cons, get_cons]
  by_cases h1 : q.witness = w <;> by_cases h2 : p.witness = w <;> simp [h1, h2]
  exact absurd (h2.trans h1.symm) hpq

end Store

end Kant
