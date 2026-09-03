/-
# Peer-to-peer replication across IPFS, iroh, libp2p, torrents and archive.org

The pastebin is a grow-only, content-addressed replica set: a node pulls
blocks from whatever sources it can reach — an IPFS gateway, an iroh
blob ticket, a libp2p gossip peer, a BitTorrent swarm, an archive.org
torrent, a UUCP spool, a QR burst off a screen — and merges them into its
local store.

Proved here:

* `sync_preserves` — merging never deletes anything a node already had;
* `sync_delivers` — after merging a feed, every block of that feed is
  served locally;
* `sync_idem` — re-merging the same feed is *literally* a no-op, so
  repeated pulls from a swarm cost nothing;
* `has_sync_iff` — what a node serves after a sync is exactly what it had
  plus what the feed carried;
* `get_sync_iff` — assuming digests do not collide, the paste served for
  a witness is fully determined by the *set* of blocks received; hence
* `sync_converges` — two nodes that received the same blocks in any
  order, from any mixture of sources, are observationally identical.
  This is the eventual-consistency statement for the whole network.
-/
import Mathlib
import RequestProject.Kant.Paste

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.Sync

open Kant

/-- Where a block came from.  All sources are equal citizens: a block is
accepted on the strength of its digest, not its provenance. -/
inductive Source
  | ipfs | iroh | libp2p | torrent | archiveOrg | uucp | qrBurst | localDisk
deriving DecidableEq, Repr

/-- A feed: the blocks offered by one source. -/
structure Feed where
  source : Source
  blocks : List Paste
deriving Repr

/-- Merge a list of blocks into a store. -/
def sync (st : Store) (ps : List Paste) : Store :=
  ps.foldl Store.put st

/-- Merge a whole feed. -/
def syncFeed (st : Store) (f : Feed) : Store := sync st f.blocks

/-- Merge many feeds, from many sources. -/
def syncAll (st : Store) (fs : List Feed) : Store := fs.foldl syncFeed st

@[simp] theorem sync_nil (st : Store) : sync st [] = st := rfl

@[simp] theorem sync_cons (st : Store) (p : Paste) (ps : List Paste) :
    sync st (p :: ps) = sync (st.put p) ps := rfl

/-- Syncing never loses data. -/
theorem sync_preserves {st : Store} {w : List Char} {q : Paste} (ps : List Paste)
    (h : st.get w = some q) : (sync st ps).get w = some q := by
  induction ps generalizing st with
  | nil => exact h
  | cons p ps ih => exact ih (Store.get_put_of_ne h)

/-- Syncing only ever adds servable witnesses. -/
theorem has_sync_mono {st : Store} {w : List Char} (ps : List Paste) (h : st.has w) :
    (sync st ps).has w := by
  induction ps generalizing st with
  | nil => exact h
  | cons p ps ih => exact ih (Store.has_put_mono h)

/-- After syncing, every block of the feed is served. -/
theorem sync_delivers {st : Store} {ps : List Paste} {p : Paste} (hp : p ∈ ps) :
    (sync st ps).has p.witness := by
  induction ps generalizing st with
  | nil => simp at hp
  | cons q ps ih =>
      rcases List.mem_cons.mp hp with rfl | hp'
      · exact has_sync_mono ps (Store.get_put_self st p)
      · exact ih hp'

/-- Re-merging the same feed changes nothing at all. -/
theorem sync_idem (st : Store) (ps : List Paste) : sync (sync st ps) ps = sync st ps := by
  induction ps generalizing st with
  | nil => rfl
  | cons p ps ih =>
      have hp : ((sync (st.put p) ps).has p.witness) :=
        has_sync_mono ps (Store.get_put_self st p)
      rw [sync_cons, sync_cons, Store.put_old hp, ih]

/-- Entries only ever come from the store or the feed. -/
theorem entries_sync_subset {st : Store} (ps : List Paste) :
    ∀ q ∈ (sync st ps).entries, q ∈ st.entries ∨ q ∈ ps := by
  induction ps generalizing st with
  | nil => intro q hq; exact Or.inl hq
  | cons p ps ih =>
      intro q hq
      rcases ih q hq with h | h
      · by_cases hput : (st.get p.witness).isSome
        · rw [Store.put_old hput] at h; exact Or.inl h
        · rw [Store.put_new hput] at h
          rcases List.mem_cons.mp h with rfl | h'
          · exact Or.inr (by simp)
          · exact Or.inl h'
      · exact Or.inr (List.mem_cons_of_mem _ h)

/-- What a node serves after a sync: exactly what it had, plus the feed. -/
theorem has_sync_iff {st : Store} (ps : List Paste) (w : List Char) :
    (sync st ps).has w ↔ (st.has w ∨ ∃ p ∈ ps, p.witness = w) := by
  constructor
  · intro h
    unfold Store.has at h ⊢
    rcases hget : (sync st ps).get w with _ | q
    · rw [hget] at h; simp at h
    · have hq : q ∈ (sync st ps).entries := List.mem_of_find?_eq_some hget
      have hw : q.witness = w := Store.get_witness hget
      rcases entries_sync_subset ps q hq with hmem | hmem
      · left
        rcases hst : st.get w with _ | r
        · exfalso
          -- `q` is in the store's entry list, so lookup cannot fail
          have hnone : (st.entries.find? (fun p => p.witness == w)) = none := hst
          have hcontra := List.find?_eq_none.mp hnone q hmem
          simp [hw] at hcontra
        · rfl
      · exact Or.inr ⟨q, hmem, hw⟩
  · rintro (h | ⟨p, hp, rfl⟩)
    · exact has_sync_mono ps h
    · exact sync_delivers hp

/-- Digests do not collide on the blocks under consideration. -/
def CollisionFree (ps : List Paste) : Prop :=
  ∀ p ∈ ps, ∀ q ∈ ps, p.witness = q.witness → p = q

/-- **The served paste is a function of the received set.**  Under
collision-freedom, a node that started empty serves `p` for witness `w`
exactly when `p` was one of the blocks it received. -/
theorem get_sync_iff {ps : List Paste} (hcf : CollisionFree ps) (w : List Char) (p : Paste) :
    (sync Store.empty ps).get w = some p ↔ (p ∈ ps ∧ p.witness = w) := by
  constructor
  · intro h
    have hq : p ∈ (sync Store.empty ps).entries := List.mem_of_find?_eq_some h
    have hw : p.witness = w := Store.get_witness h
    rcases entries_sync_subset ps p hq with hmem | hmem
    · simp [Store.empty] at hmem
    · exact ⟨hmem, hw⟩
  · rintro ⟨hp, rfl⟩
    have hhas : (sync Store.empty ps).has p.witness := sync_delivers hp
    unfold Store.has at hhas
    rcases hget : (sync Store.empty ps).get p.witness with _ | q
    · rw [hget] at hhas; simp at hhas
    · have hq : q ∈ (sync Store.empty ps).entries := List.mem_of_find?_eq_some hget
      have hw : q.witness = p.witness := Store.get_witness hget
      rcases entries_sync_subset ps q hq with hmem | hmem
      · simp [Store.empty] at hmem
      · rw [hcf q hmem p hp hw]

/-- **Eventual consistency.**  Two nodes that received the same blocks —
in any order, from any mixture of IPFS, iroh, libp2p, torrent,
archive.org or sneakernet sources — serve exactly the same content. -/
theorem sync_converges {ps₁ ps₂ : List Paste} (hperm : ps₁.Perm ps₂)
    (hcf : CollisionFree ps₁) (w : List Char) :
    (sync Store.empty ps₁).get w = (sync Store.empty ps₂).get w := by
  have hcf₂ : CollisionFree ps₂ := by
    intro p hp q hq h
    exact hcf p (hperm.mem_iff.mpr hp) q (hperm.mem_iff.mpr hq) h
  rcases h₁ : (sync Store.empty ps₁).get w with _ | p
  · rcases h₂ : (sync Store.empty ps₂).get w with _ | q
    · rfl
    · exfalso
      obtain ⟨hq, hw⟩ := (get_sync_iff hcf₂ w q).mp h₂
      have hsome : (sync Store.empty ps₁).get w = some q :=
        (get_sync_iff hcf w q).mpr ⟨hperm.mem_iff.mpr hq, hw⟩
      rw [h₁] at hsome
      simp at hsome
  · obtain ⟨hp, hw⟩ := (get_sync_iff hcf w p).mp h₁
    exact ((get_sync_iff hcf₂ w p).mpr ⟨hperm.mem_iff.mp hp, hw⟩).symm

/-- Syncing feeds from several sources is the same as syncing their
concatenation: provenance is irrelevant, only the blocks matter. -/
theorem syncAll_eq_sync (st : Store) (fs : List Feed) :
    syncAll st fs = sync st (fs.flatMap Feed.blocks) := by
  induction fs generalizing st with
  | nil => rfl
  | cons f fs ih =>
      have hsync : ∀ (st : Store) (as bs : List Paste),
          sync st (as ++ bs) = sync (sync st as) bs := by
        intro st as bs
        induction as generalizing st with
        | nil => rfl
        | cons a as iha => simpa using iha (st.put a)
      simp only [syncAll, List.foldl_cons, syncFeed, List.flatMap_cons, hsync]
      exact ih (sync st f.blocks)

end Kant.Sync
