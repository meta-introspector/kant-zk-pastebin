/-
# Screens, the camera switch, and the guided first run

The client used to be one long page: every control for every feature,
visible at once, with the camera impossible to switch off once it was
started.  This module specifies the small application that replaces it.

* **Screens** (`Screen`): *welcome*, *share*, *join*, *scan*, *chat*,
  *more*.  One thing at a time, and `back` always goes home.
* **The camera switch** (`Event.startCamera`, `Event.stopCamera`): a
  scan is a screen you can leave.  Proved: `camera_off_after_stop`,
  `camera_off_after_back`, `camera_off_after_goto`,
  `camera_off_after_leave`, `camera_off_after_join`, and the invariant
  `camera_implies_scan` — the camera is never left running behind
  another screen.
* **One link, one code** (`shareText`, `qrText`): what the share screen
  shows, what its code carries, and what the join screen accepts are the
  same string — `qrText_eq_shareText`, `share_then_join`,
  `join_lands_in_room`.
* **The guided first run** (`Task`, `nextTask`, `prompt`, `speech`): a
  short list of things to do, each with a line to speak aloud.  Proved:
  `prompt_ne_empty` and `promptFor_ne_empty` (there is always a line to
  say), `nextTask_screen` (the guide names the
  screen the task is done on), `step_progress_mono` (a task once done
  stays done), `nextTask_eq_none_iff` (the guide finishes exactly when
  everything is done), `first_run_completes` and
  `join_run_completes` (the two scripted first runs really do finish),
  and `hushed_says_nothing` (the voice can be turned off).
-/
import Mathlib
import RequestProject.Kant.Text
import RequestProject.Kant.Rendezvous
import RequestProject.Kant.SiteCard
import RequestProject.Kant.InviteCard
import RequestProject.Kant.Join

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.Onboarding

open Kant Kant.Text Kant.Rendezvous Kant.SiteCard

/-! ## Screens -/

/-- One screen of the client. -/
inductive Screen
  /-- The first screen: what this is, and the two ways in. -/
  | welcome
  /-- Show my link and my code. -/
  | share
  /-- Paste somebody's link. -/
  | join
  /-- Point the camera at somebody's code. -/
  | scan
  /-- The room. -/
  | chat
  /-- Everything else: the pastebin, the sneakernet, the workbench. -/
  | more
deriving DecidableEq, Repr

/-! ## What the user did -/

/-- An event the interface can produce. -/
inductive Event
  /-- Tap through to a screen. -/
  | goto (s : Screen)
  /-- The back button. -/
  | back
  /-- Open a fresh room. -/
  | createRoom
  /-- Copy the link (or show the code) — the room has been shared. -/
  | copyLink
  /-- Switch the camera on. -/
  | startCamera
  /-- Switch the camera off.  Always available. -/
  | stopCamera
  /-- Text arrived: pasted into the join box, or read by the camera. -/
  | joinText (t : List Char)
  /-- Send a line to the room. -/
  | say
  /-- Leave the room. -/
  | leave
  /-- Silence the voice. -/
  | hush
  /-- Let the voice speak again. -/
  | unhush

/-! ## The guided first run -/

/-- One thing the newcomer is asked to do. -/
inductive Task
  /-- Get into a room: open one, or follow somebody's link. -/
  | getIn
  /-- Hand the link to somebody else. -/
  | shareIt
  /-- Say something in the room. -/
  | sayHello
deriving DecidableEq, Repr

/-- How far the newcomer has got.  Nothing here is ever unlearned. -/
structure Progress where
  /-- In a room, either by opening one or by following a link. -/
  gotIn : Bool
  /-- The link has been handed over. -/
  sharedIt : Bool
  /-- Something has been said in the room. -/
  saidHello : Bool
deriving DecidableEq, Repr

/-- The whole state of the interface. -/
structure State where
  /-- The screen on show. -/
  screen : Screen
  /-- Is the camera running? -/
  camera : Bool
  /-- Are we in a room? -/
  inRoom : Bool
  /-- Has the voice been silenced? -/
  hushed : Bool
  /-- How far the guide has got. -/
  progress : Progress
deriving DecidableEq, Repr

/-- A first visit: the welcome screen, no camera, no room, nothing done. -/
def start : State := ⟨Screen.welcome, false, false, false, ⟨false, false, false⟩⟩

/-- One event. -/
def step (s : State) : Event → State
  | .goto t => { s with screen := t, camera := s.camera && (t == Screen.scan) }
  | .back => { s with screen := Screen.welcome, camera := false }
  | .createRoom =>
      { s with screen := Screen.share, camera := false, inRoom := true,
               progress := { s.progress with gotIn := true } }
  | .copyLink =>
      { s with progress := { s.progress with sharedIt := s.progress.sharedIt || s.inRoom } }
  | .startCamera => { s with screen := Screen.scan, camera := true }
  | .stopCamera => { s with camera := false }
  | .joinText t =>
      match Kant.Join.findInvite t with
      | some _ =>
          { s with screen := Screen.chat, camera := false, inRoom := true,
                   progress := { s.progress with gotIn := true } }
      | none => s
  | .say =>
      { s with progress := { s.progress with saidHello := s.progress.saidHello || s.inRoom } }
  | .leave => { s with screen := Screen.welcome, camera := false, inRoom := false }
  | .hush => { s with hushed := true }
  | .unhush => { s with hushed := false }

/-- A run of events. -/
def run (s : State) : List Event → State
  | [] => s
  | e :: es => run (step s e) es

@[simp] theorem run_nil (s : State) : run s [] = s := rfl

@[simp] theorem run_cons (s : State) (e : Event) (es : List Event) :
    run s (e :: es) = run (step s e) es := rfl

/-! ## The camera can always be switched off -/

/-- **The off button always works.** -/
@[simp] theorem camera_off_after_stop (s : State) : (step s .stopCamera).camera = false := rfl

/-- **Going back switches the camera off.** -/
@[simp] theorem camera_off_after_back (s : State) : (step s .back).camera = false := rfl

/-- **Leaving the room switches the camera off.** -/
@[simp] theorem camera_off_after_leave (s : State) : (step s .leave).camera = false := rfl

/-- **Tapping through to any other screen switches the camera off.** -/
theorem camera_off_after_goto {s : State} {t : Screen} (h : t ≠ Screen.scan) :
    (step s (.goto t)).camera = false := by
  simp [step, h]

/-- **A code that was read switches the camera off**: the scan screen
never outlives the scan. -/
theorem camera_off_after_join {s : State} {t : List Char} {i : Invite}
    (h : Kant.Join.findInvite t = some i) : (step s (.joinText t)).camera = false := by
  simp [step, h]

/-- The states the interface can actually be in. -/
inductive Reachable : State → Prop
  /-- A first visit is reachable. -/
  | start : Reachable start
  /-- Anything one event away from a reachable state is reachable. -/
  | step {s : State} (e : Event) : Reachable s → Reachable (step s e)

/-- **The camera never runs behind another screen.**  In every state the
interface can reach, a running camera means the scan screen is the one on
show — so the button that stops it is always in front of the user. -/
theorem camera_implies_scan {s : State} (h : Reachable s) :
    s.camera = true → s.screen = Screen.scan := by
  induction h with
  | start => intro hc; exact absurd hc (by decide)
  | step e _ ih =>
      cases e with
      | goto t =>
          intro hc
          simp only [step] at hc ⊢
          rcases Bool.and_eq_true _ _ |>.mp hc with ⟨_, ht⟩
          exact of_decide_eq_true ht
      | back => intro hc; exact absurd hc (by simp [step])
      | createRoom => intro hc; exact absurd hc (by simp [step])
      | copyLink => exact ih
      | startCamera => intro _; rfl
      | stopCamera => intro hc; exact absurd hc (by simp [step])
      | joinText t =>
          intro hc
          cases hf : Kant.Join.findInvite t with
          | some j => simp [step, hf] at hc
          | none => simp only [step, hf] at hc ⊢; exact ih hc
      | say => exact ih
      | leave => intro hc; exact absurd hc (by simp [step])
      | hush => intro hc; exact ih hc
      | unhush => intro hc; exact ih hc

/-- **Back always goes home**, from wherever the user is. -/
@[simp] theorem back_goes_home (s : State) : (step s .back).screen = Screen.welcome := rfl

/-- **Every screen is one tap away.** -/
theorem screen_reachable (t : Screen) : ∃ e : Event, (step start e).screen = t :=
  ⟨.goto t, rfl⟩

/-! ## One link, one code -/

/-- The one piece of text the share screen offers: the whole page link. -/
def shareText (c : Config) (i : Invite) : List Char := Kant.InviteCard.inviteUrl c i

/-- What the one code on that screen carries. -/
def qrText (c : Config) (d : Kant.InviteCard.Dress) (i : Invite) : List Char :=
  (Kant.InviteCard.inviteCard c d i).url

/-- **The code carries exactly the link that is offered**: there are not
two things to share, only one. -/
theorem qrText_eq_shareText (c : Config) (d : Kant.InviteCard.Dress) (i : Invite) :
    qrText c d i = shareText c i := rfl

/-- **What one side shows, the other side accepts.**  The link from the
share screen, pasted or scanned into the join screen, is the invitation
that was meant. -/
theorem share_then_join {c : Config} (ho : Kant.Join.BlankFree c.origin) {i : Invite}
    (hi : i.Wire) : Kant.Join.findInvite (shareText c i) = some i :=
  Kant.Join.findInvite_inviteUrl ho hi

/-- **Handing the link over puts the other person in the room** — on the
chat screen, with the camera off. -/
theorem join_lands_in_room {c : Config} (ho : Kant.Join.BlankFree c.origin) {i : Invite}
    (hi : i.Wire) (s : State) :
    (step s (.joinText (shareText c i))).inRoom = true ∧
      (step s (.joinText (shareText c i))).screen = Screen.chat ∧
      (step s (.joinText (shareText c i))).camera = false := by
  have h := share_then_join ho hi
  refine ⟨?_, ?_, ?_⟩ <;> simp [step, h]

/-! ## What the guide says -/

/-- The next thing to do, given how far the newcomer has got. -/
def nextTask (p : Progress) : Option Task :=
  if !p.gotIn then some Task.getIn
  else if !p.sharedIt then some Task.shareIt
  else if !p.saidHello then some Task.sayHello
  else none

/-- The screen a task is done on. -/
def screenFor : Task → Screen
  | .getIn => Screen.welcome
  | .shareIt => Screen.share
  | .sayHello => Screen.chat

/-- What the guide says out loud for each task. -/
def prompt : Task → String
  | .getIn =>
      "Step one of three. Tap Start a room to make a new room, or tap Join and paste the link somebody sent you."
  | .shareIt =>
      "Step two of three. This is your link and your code. Copy the link into any chat, or let the other person point their camera at the code."
  | .sayHello =>
      "Step three of three. Type a line and send it. Everyone who followed your link sees it."

/-- What the guide says when there is nothing left to do. -/
def doneWords : String :=
  "That is everything. You have a room, you have shared it, and you have said something in it."

/-- The line the guide would say in this state. -/
def promptFor (s : State) : String :=
  match nextTask s.progress with
  | some t => prompt t
  | none => doneWords

/-- What is actually spoken: nothing at all when the voice is hushed. -/
def speech (s : State) : String := if s.hushed then "" else promptFor s

/-- **There is always something to say.** -/
theorem prompt_ne_empty (t : Task) : prompt t ≠ "" := by cases t <;> simp [prompt]

theorem doneWords_ne_empty : doneWords ≠ "" := by simp [doneWords]

/-- The guide always has a line for the state it is in. -/
theorem promptFor_ne_empty (s : State) : promptFor s ≠ "" := by
  unfold promptFor
  cases h : nextTask s.progress with
  | some t => exact prompt_ne_empty t
  | none => exact doneWords_ne_empty

/-- **The voice can be turned off**, and then it really is silent. -/
theorem hushed_says_nothing (s : State) : speech (step s .hush) = "" := by
  simp [speech, step]

/-- With the voice on, what is spoken is the line for the current task. -/
theorem unhushed_speaks (s : State) : speech (step s .unhush) = promptFor s := by
  simp [speech, step, promptFor]

/-- **The guide sends the user to the screen where the task is done.** -/
theorem nextTask_screen {p : Progress} {t : Task} (h : nextTask p = some t) :
    screenFor t = Screen.welcome ∨ screenFor t = Screen.share ∨ screenFor t = Screen.chat := by
  cases t
  · exact Or.inl rfl
  · exact Or.inr (Or.inl rfl)
  · exact Or.inr (Or.inr rfl)

/-- **The guide stops exactly when everything is done.** -/
theorem nextTask_eq_none_iff (p : Progress) :
    nextTask p = none ↔ p.gotIn = true ∧ p.sharedIt = true ∧ p.saidHello = true := by
  cases p with
  | mk a b c => cases a <;> cases b <;> cases c <;> simp [nextTask]

/-- One progress record is at least as far along as another. -/
def Progress.le (p q : Progress) : Prop :=
  (p.gotIn = true → q.gotIn = true) ∧ (p.sharedIt = true → q.sharedIt = true) ∧
    (p.saidHello = true → q.saidHello = true)

/-- **A task once done stays done**: nothing the user can do sends the
guide backwards. -/
theorem step_progress_mono (s : State) (e : Event) : s.progress.le (step s e).progress := by
  cases e with
  | goto t => exact ⟨id, id, id⟩
  | back => exact ⟨id, id, id⟩
  | createRoom => exact ⟨fun _ => rfl, id, id⟩
  | copyLink => refine ⟨id, fun h => ?_, id⟩; simp [step, h]
  | startCamera => exact ⟨id, id, id⟩
  | stopCamera => exact ⟨id, id, id⟩
  | joinText t =>
      cases hf : Kant.Join.findInvite t with
      | some j => refine ⟨fun h => ?_, fun h => ?_, fun h => ?_⟩ <;> simp [step, hf, h]
      | none => simp [Progress.le, step, hf]
  | say => refine ⟨id, id, fun h => ?_⟩; simp [step, h]
  | leave => exact ⟨id, id, id⟩
  | hush => exact ⟨id, id, id⟩
  | unhush => exact ⟨id, id, id⟩

/-- **The scripted first run finishes.**  Open a room, copy the link,
say something: the guide has nothing left to ask for, the user is in a
room and the camera is off. -/
theorem first_run_completes :
    nextTask (run start [.createRoom, .copyLink, .say]).progress = none ∧
      (run start [.createRoom, .copyLink, .say]).inRoom = true ∧
      (run start [.createRoom, .copyLink, .say]).camera = false := by
  refine ⟨rfl, rfl, rfl⟩

/-- **The other scripted first run finishes too.**  Somebody who arrives
by following a link is in the room, on the chat screen, with the camera
off, and is asked only for the two things left. -/
theorem join_run_completes {c : Config} (ho : Kant.Join.BlankFree c.origin) {i : Invite}
    (hi : i.Wire) :
    (run start [.joinText (shareText c i), .copyLink, .say]).progress.gotIn = true ∧
      (run start [.joinText (shareText c i), .copyLink, .say]).inRoom = true ∧
      (run start [.joinText (shareText c i), .copyLink, .say]).camera = false ∧
      nextTask (run start [.joinText (shareText c i), .copyLink, .say]).progress = none := by
  have h := share_then_join ho hi
  refine ⟨?_, ?_, ?_, ?_⟩ <;>
    simp [run, step, h, nextTask, start]

end Kant.Onboarding
