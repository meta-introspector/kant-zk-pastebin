/-
# Running the whole thing by hand, in a chat, with nothing running anywhere

`Kant.Uucp` proves that a relay is redundant: two nodes that swap bags
end up displaying the same transcript.  This module turns that into the
**procedure a person follows**: a short, numbered script of moves, each
of which is either *copy this out of the app and send it in the chat* or
*paste what they sent you back into the app*.

* `Move.needsServer` is `false` for both moves, and `script_serverless`
  and `logScript_serverless` say that a whole session — connecting,
  talking, and handing over the run — asks for nothing else;
* `run_delivers`, `run_delivers_back` and `run_agree` say the script
  works: after the four steps both sides show the same conversation;
* `logScript_delivers` says the run (`Kant.ShareLog`) survives the same
  treatment, in as many chat messages as it takes, in any order;
* `carry_resolves` and `carry_agrees` say the same about a *post*: a
  block copied into a chat and pasted on the other side lands in the
  other store under the very same address.
-/
import Mathlib
import RequestProject.Kant.ShareLog

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.Handoff

open Kant Kant.Bytes Kant.Text Kant.Clipboard Kant.Relay Kant.Sneakernet Kant.Uucp
open Kant.Diagnostics Kant.ShareLog

/-! ## What a person is asked to do -/

/-- One thing a human does.  There is nothing else: no fetch, no poll, no
socket. -/
inductive Move
  /-- Copy this code out of the app and send it in the chat. -/
  | copyOut (code : List Char)
  /-- Paste what they sent you into the app. -/
  | pasteIn
deriving DecidableEq, Repr

/-- **No move needs a server.** -/
def Move.needsServer : Move → Bool
  | .copyOut _ => false
  | .pasteIn => false

@[simp] theorem Move.needsServer_eq_false (m : Move) : m.needsServer = false := by
  cases m <;> rfl

/-- The code a move puts in the chat, if it puts one there. -/
def Move.payload : Move → Option (List Char)
  | .copyOut c => some c
  | .pasteIn => none

/-- One numbered instruction on the screen. -/
structure Step where
  /-- Its place in the script, from 1. -/
  number : Nat
  /-- Whose turn it is. -/
  actor : List Char
  /-- The sentence shown to that person. -/
  instruction : List Char
  /-- What they do. -/
  move : Move
deriving DecidableEq, Repr

/-- A script needs no server when none of its steps does. -/
def Serverless (steps : List Step) : Prop := ∀ s ∈ steps, s.move.needsServer = false

/-- **Any script at all is serverless**, because no move can ask for a
server in the first place.  This is the whole point of the mode: the
procedure is closed under everything the app can tell you to do. -/
theorem serverless_all (steps : List Step) : Serverless steps :=
  fun s _ => Move.needsServer_eq_false s.move

/-- The codes a script asks you to send. -/
def codes (steps : List Step) : List (List Char) := steps.filterMap (fun s => s.move.payload)

/-! ## The four steps that connect two people through any chat -/

/-- "Copy this and send it in the chat." -/
def sayCopy : List Char := "copy this and send it in the chat".toList

/-- "Paste what they sent you into the box." -/
def sayPaste : List Char := "paste what they sent you into the box".toList

/-- The script shown to two people who have only a chat window between
them: you send yours, they paste it, they send theirs, you paste it. -/
def script (a b : Node) : List Step :=
  [ ⟨1, a.name, sayCopy, .copyOut a.bag⟩
  , ⟨2, b.name, sayPaste, .pasteIn⟩
  , ⟨3, b.name, sayCopy, .copyOut (b.paste a.bag).bag⟩
  , ⟨4, a.name, sayPaste, .pasteIn⟩ ]

@[simp] theorem script_length (a b : Node) : (script a b).length = 4 := rfl

/-- **Four steps, no server.** -/
theorem script_serverless (a b : Node) : Serverless (script a b) := serverless_all _

/-- The two codes that go into the chat: your bag, then theirs. -/
@[simp] theorem codes_script (a b : Node) :
    codes (script a b) = [a.bag, (b.paste a.bag).bag] := rfl

/-- Everything sent into the chat is plain ASCII, so any chat, any SMS
and any QR code carries it unchanged. -/
theorem codes_script_isAscii (a b : Node) : ∀ c ∈ codes (script a b), IsAscii c := by
  intro c hc
  rw [codes_script] at hc
  rcases List.mem_cons.mp hc with rfl | hc
  · exact isAscii_packBag _
  · rcases List.mem_cons.mp hc with rfl | hc
    · exact isAscii_packBag _
    · exact absurd hc (by simp)

/-- Carrying the script out: they paste yours, you paste theirs. -/
def run (a b : Node) : Node × Node :=
  let b' := b.paste a.bag
  (a.paste b'.bag, b')

@[simp] theorem run_snd (a b : Node) : (run a b).2 = b.paste a.bag := rfl

@[simp] theorem run_fst (a b : Node) : (run a b).1 = a.paste (b.paste a.bag).bag := rfl

/-- **Step 2 delivers**: everything you hold, they hold. -/
theorem run_delivers {a b : Node} (ha : Node.Wired a) {x : Msg} (hx : x ∈ a.spool) :
    x ∈ (run a b).2.spool := handoff ha hx

/-- **Step 4 delivers the other way**: everything they held, you hold. -/
theorem run_delivers_back {a b : Node} (ha : Node.Wired a) (hb : Node.Wired b) {x : Msg}
    (hx : x ∈ b.spool) : x ∈ (run a b).1.spool := by
  have hb' : Node.Wired (b.paste a.bag) :=
    Node.paste_wired hb (by
      intro ms hms m hm
      rw [openBag_bag ha, Option.some.injEq] at hms
      subst hms
      exact wired_view ha m hm)
  exact handoff hb' (Node.paste_monotone hx)

/-- Nothing you already had is lost. -/
theorem run_keeps {a b : Node} {x : Msg} (hx : x ∈ a.spool) : x ∈ (run a b).1.spool :=
  Node.paste_monotone hx

/-- After the script, the two sides hold the same messages. -/
theorem run_mem {a b : Node} (ha : Node.Wired a) (hb : Node.Wired b) (x : Msg) :
    x ∈ (run a b).1.spool ↔ x ∈ (run a b).2.spool := by
  have hb' : Node.Wired (b.paste a.bag) :=
    Node.paste_wired hb (by
      intro ms hms m hm
      rw [openBag_bag ha, Option.some.injEq] at hms
      subst hms
      exact wired_view ha m hm)
  constructor
  · intro hx
    rcases Node.mem_paste_iff.mp hx with h | ⟨ms, hms, h⟩
    · exact run_delivers ha h
    · rw [openBag_bag hb', Option.some.injEq] at hms
      subst hms
      exact mem_transcript.mp h
  · intro hx
    exact handoff hb' hx

/-- **The script works.**  Two people, one chat window, four copy-pastes,
and both sides display exactly the same conversation — with no relay, no
server and no network between them. -/
theorem run_agree {a b : Node} (ha : Node.Wired a) (hb : Node.Wired b)
    (hna : a.spool.Nodup) (hnb : b.spool.Nodup) : (run a b).1.view = (run a b).2.view := by
  have hb' : Node.Wired (b.paste a.bag) :=
    Node.paste_wired hb (by
      intro ms hms m hm
      rw [openBag_bag ha, Option.some.injEq] at hms
      subst hms
      exact wired_view ha m hm)
  have ha' : Node.Wired (a.paste (b.paste a.bag).bag) :=
    Node.paste_wired ha (by
      intro ms hms m hm
      rw [openBag_bag hb', Option.some.injEq] at hms
      subst hms
      exact wired_view hb' m hm)
  have hperm : (run a b).1.spool.Perm (run a b).2.spool :=
    (List.perm_ext_iff_of_nodup (Node.paste_nodup hna _) (Node.paste_nodup hnb _)).mpr
      (run_mem ha hb)
  exact transcript_perm ha' hperm

/-- Writing a transmissible message keeps the node transmissible. -/
theorem wired_write {a : Node} {room : List Char} {body : Blob} (ha : Node.Wired a)
    (hnew : (Msg.mk room a.name a.clock body).Wire) : Node.Wired (a.write room body) := by
  intro m hm
  rcases mem_absorb_iff.mp hm with h | h
  · exact ha m h
  · rcases List.mem_singleton.mp h with rfl
    exact hnew

/-- **Saying something new and running the script again delivers it.**
A conversation carried entirely by hand keeps going: write, copy, send,
paste, and what you said is on the other screen. -/
theorem run_after_write {a b : Node} {room : List Char} {body : Blob}
    (ha : Node.Wired a) (hnew : (Msg.mk room a.name a.clock body).Wire) {x : Msg}
    (hx : x ∈ (a.write room body).spool) :
    x ∈ (run (a.write room body) b).2.spool :=
  run_delivers (wired_write ha hnew) hx

/-- What you just said reaches them. -/
theorem run_after_write_new {a b : Node} {room : List Char} {body : Blob}
    (ha : Node.Wired a) (hnew : (Msg.mk room a.name a.clock body).Wire) :
    (Msg.mk room a.name a.clock body) ∈ (run (a.write room body) b).2.spool :=
  run_after_write ha hnew (mem_absorb_iff.mpr (Or.inr (by simp)))

/-! ## Handing the run over in the same chat -/

/-- "Send this message, then the next one." -/
def sayPart : List Char := "send this message, then the next one".toList

/-- The steps that hand the run over as numbered chat messages. -/
def logScript (limit : Nat) (who : List Char) (r : Report) : List Step :=
  (chatParts limit r).zipIdx.map (fun p => ⟨p.2 + 1, who, sayPart, .copyOut p.1⟩)

/-- **Sharing the run needs no server either.** -/
theorem logScript_serverless (limit : Nat) (who : List Char) (r : Report) :
    Serverless (logScript limit who r) := serverless_all _

@[simp] theorem codes_logScript (limit : Nat) (who : List Char) (r : Report) :
    codes (logScript limit who r) = chatParts limit r := by
  unfold codes logScript
  rw [List.filterMap_map]
  have : (fun p : List Char × Nat => (Move.copyOut p.1).payload) =
      fun p : List Char × Nat => some p.1 := rfl
  simp [Function.comp_def, Move.payload, List.zipIdx_map_fst]

/-- One numbered step per chat message. -/
@[simp] theorem logScript_length (limit : Nat) (who : List Char) (r : Report) :
    (logScript limit who r).length = (chatParts limit r).length := by
  simp [logScript]

/-- **Following the steps hands the run over intact.** -/
theorem logScript_delivers {limit : Nat} (hlim : 0 < limit) {who : List Char} {r : Report}
    (h : r.Wire) : readChatParts (codes (logScript limit who r)) = some r := by
  rw [codes_logScript]
  exact readChatParts_chatParts hlim h

/-- **Every message the script asks you to send fits in a tweet.** -/
theorem logScript_fits_tweet {who : List Char} {r : Report}
    (hn : (chunk 100 (asciiBytes (logText r))).length < 256 ^ 3) :
    ∀ c ∈ codes (logScript 100 who r), c.length ≤ Carrier.tweet.capacity := by
  rw [codes_logScript]
  exact chatParts_fit_tweet hn

/-! ## Handing a post over in the same chat

The store is content-addressed, so a block that travels by hand lands on
the other side under exactly the address it left with. -/

/-- Paste a copied post into your own store.  Anything that does not read
back, or whose content and witness disagree, leaves the store alone
(`Kant.Clipboard.toPaste_eq_none_of_mismatch`). -/
def carry (st : Store) (s : List Char) : Store :=
  match Kant.Clipboard.pasteText s with
  | some p => st.put p
  | none => st

/-- **A post carried by hand arrives.**  After pasting the code, the
receiving store answers to the post's own address. -/
theorem carry_resolves {p : Paste} (h : Kant.Clipboard.Copyable p) (st : Store) :
    ((carry st (Kant.Clipboard.copyText p)).get p.witness).isSome := by
  unfold carry
  rw [Kant.Clipboard.pasteText_copyText h]
  exact Store.get_put_self st p

/-- **Both sides then hold the same block.**  Whatever either store
answers with at that address is a paste carrying that address, so the
two agree by content and not by trust. -/
theorem carry_agrees {p : Paste} {st₁ st₂ : Store} {q₁ q₂ : Paste}
    (h₁ : st₁.get p.witness = some q₁) (h₂ : st₂.get p.witness = some q₂) :
    q₁.witness = q₂.witness := by
  rw [Store.get_witness h₁, Store.get_witness h₂]

/-- Carrying a block you already hold changes nothing. -/
theorem carry_idem {p : Paste} (h : Kant.Clipboard.Copyable p) (st : Store) :
    carry (carry st (Kant.Clipboard.copyText p)) (Kant.Clipboard.copyText p) =
      carry st (Kant.Clipboard.copyText p) := by
  unfold carry
  rw [Kant.Clipboard.pasteText_copyText h]
  exact Store.put_idem st p

/-- Carrying never loses what the store already had. -/
theorem carry_monotone {st : Store} {w : List Char} (s : List Char) (h : st.has w) :
    (carry st s).has w := by
  unfold carry
  cases Kant.Clipboard.pasteText s with
  | none => exact h
  | some p => exact Store.has_put_mono h

/-- **The run, posted and then carried by hand, arrives as a post.**
Posting the shared run and sending its clipboard text through the chat
puts the very same block in the other store. -/
theorem carry_postedLog {id ts : List Char} (hid : IsAscii id) (hts : IsAscii ts)
    (r : Report) (st : Store) :
    ((carry st (Kant.Clipboard.copyText (logPaste id ts r))).get (logPaste id ts r).witness).isSome :=
  carry_resolves (copyable_logPaste hid hts r) st


/-! ## Golden vectors shared with the JavaScript -/

section Guards

private def guardEvent : Event := ⟨0, 12, .info, .app, "page opened".toList,
  "https://example.org/".toList⟩

private def guardReport : Report :=
  shareReport [] .noRoom "swordfish".toList "".toList ⟨100, [guardEvent], 0⟩

private def guardNodeA : Node := (Node.blank "a".toList).write "room".toList (asciiBytes "hi".toList)

private def guardNodeB : Node := Node.blank "b".toList

#guard (script guardNodeA guardNodeB).length = 4
#guard (codes (script guardNodeA guardNodeB)).length = 2
#guard sayCopy = "copy this and send it in the chat".toList
#guard sayPaste = "paste what they sent you into the box".toList
#guard sayPart = "send this message, then the next one".toList
#guard (logScript 100 "you".toList guardReport).length =
  (chatParts 100 guardReport).length
#guard ((run guardNodeA guardNodeB).2.spool).length = 1

end Guards

end Kant.Handoff
