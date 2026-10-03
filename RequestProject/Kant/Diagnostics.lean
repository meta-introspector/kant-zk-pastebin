/-
# Diagnostics: a detailed net and error log, and a whole run you can share

Every transport error used to be swallowed by a bare `catch {}`, so a
relay that was never contacted, a relay that answered `404`, and a relay
that worked all looked identical from the outside.  This module
specifies the log that replaces the silence, and the report that carries
a whole run into a bug message.

## The log

An `Event` is one line of the run: a sequence number, a timestamp, a
level (`info`/`warn`/`error`), the area it came from (`config`, `probe`,
`relay`, `socket`, `bus`, `mesh`, `signal`, `ingest`, `app`), a
human-readable line and a machine-readable detail.  Events go into a
`Log`, a bounded ring: it never grows without limit, it never renumbers
what it already holds, and — the point of a log — it never drops the
event that just happened.

* `parseEvent_printEvent`, `parseLog_renderLog` — a run written out reads
  back exactly, event for event, so the text pasted into a bug report is
  the run and not a summary of it;
* `Log.add_length_le`, `Log.add_total` — bounded, and every event is
  either held or counted in `dropped`: the log can lose old lines but it
  cannot lose the count of them;
* `Log.add_getLast` — the newest event survives every trim;
* `Log.wf_empty`, `Log.Wf.record` — sequence numbers strictly increase,
  so a shared run is in the order it happened.

## Sharing it without leaking the room

A room is the digest of a secret, and the invite code carries that
secret.  A log pasted into a public bug report must not.  `Log.share`
withholds any event that quotes a secret, and `share_no_secret` proves
that what is left quotes none of them — not as a substring, anywhere —
while `share_keeps` proves nothing else is withheld.  `ref` gives the
short, one-way handle used to name a room instead of printing it.

## The diagnostic page

A `Report` is the verdict (`Kant.Connectivity.diagnose`), the room's
handle, the relay in use and the shared log.
`parseReport_renderReport` — the page's "copy the whole run" button
produces text that reads back as the same report; `report_events_clean`
— everything in it has been through the filter.
-/
import Mathlib
import RequestProject.Kant.Bytes
import RequestProject.Kant.Text
import RequestProject.Kant.Clipboard
import RequestProject.Kant.SiteCard
import RequestProject.Kant.Connectivity

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.Diagnostics

open Kant Kant.Bytes Kant.Text Kant.Clipboard Kant.Connectivity

/-! ## Levels and areas -/

/-- How loud an event is. -/
inductive Level
  /-- Ordinary progress. -/
  | info
  /-- Something is wrong but the client carried on. -/
  | warn
  /-- Something failed. -/
  | error
deriving DecidableEq, Repr

/-- The wire code of a level. -/
def Level.code : Level → UInt8
  | .info => 1
  | .warn => 2
  | .error => 3

/-- Read a level code. -/
def levelOfCode : UInt8 → Option Level
  | 1 => some .info
  | 2 => some .warn
  | 3 => some .error
  | _ => none

@[simp] theorem levelOfCode_code (l : Level) : levelOfCode l.code = some l := by
  cases l <;> rfl

/-- Which part of the client an event came from. -/
inductive Area
  /-- Reading `kant.config`, and what was decided from it. -/
  | config
  /-- Probing a relay's `/health`. -/
  | probe
  /-- HTTP traffic with the relay. -/
  | relay
  /-- The relay WebSocket. -/
  | socket
  /-- The same-browser `BroadcastChannel`. -/
  | bus
  /-- The WebRTC mesh. -/
  | mesh
  /-- Signalling lines. -/
  | signal
  /-- Lines accepted or refused by the client. -/
  | ingest
  /-- The page itself: uncaught errors, rejections, user actions. -/
  | app
deriving DecidableEq, Repr

/-- The wire code of an area. -/
def Area.code : Area → UInt8
  | .config => 1
  | .probe => 2
  | .relay => 3
  | .socket => 4
  | .bus => 5
  | .mesh => 6
  | .signal => 7
  | .ingest => 8
  | .app => 9

/-- Read an area code. -/
def areaOfCode : UInt8 → Option Area
  | 1 => some .config
  | 2 => some .probe
  | 3 => some .relay
  | 4 => some .socket
  | 5 => some .bus
  | 6 => some .mesh
  | 7 => some .signal
  | 8 => some .ingest
  | 9 => some .app
  | _ => none

@[simp] theorem areaOfCode_code (a : Area) : areaOfCode a.code = some a := by
  cases a <;> rfl

/-! ## One event -/

/-- One line of the run. -/
structure Event where
  /-- Position in the run; strictly increasing, never reused. -/
  seq : Nat
  /-- Milliseconds since the page was opened. -/
  ms : Nat
  /-- How loud it is. -/
  level : Level
  /-- Where it came from. -/
  area : Area
  /-- The sentence shown to the reader. -/
  text : List Char
  /-- The machine-readable detail: a URL, a status, an error message. -/
  detail : List Char
deriving DecidableEq, Repr

/-- An event whose text travels through a text channel unchanged. -/
structure Event.Wire (e : Event) : Prop where
  /-- The sentence is ASCII. -/
  text : IsAscii e.text
  /-- The detail is ASCII. -/
  detail : IsAscii e.detail

/-- The tag of a log line. -/
def tagLog : Blob := asciiBytes "kzlog".toList

/-- An event as an envelope. -/
def ofEvent (e : Event) : Envelope :=
  { tag := tagLog,
    fields := [natToBytesBE e.seq, natToBytesBE e.ms, [e.level.code], [e.area.code],
      asciiBytes e.text, asciiBytes e.detail] }

/-- Read an event back out of an envelope. -/
def toEvent (e : Envelope) : Option Event :=
  if e.tag ≠ tagLog then none else
    match e.fields with
    | [s, t, [lc], [ac], tx, dt] =>
        match levelOfCode lc, areaOfCode ac with
        | some l, some a =>
            some ⟨bytesBEToNat s, bytesBEToNat t, l, a, asciiChars tx, asciiChars dt⟩
        | _, _ => none
    | _ => none

/-- **An event survives the wire.** -/
theorem toEvent_ofEvent {e : Event} (h : e.Wire) : toEvent (ofEvent e) = some e := by
  cases e
  simp [toEvent, ofEvent, bytesBEToNat_natToBytesBE, asciiChars_asciiBytes h.text,
    asciiChars_asciiBytes h.detail]

/-- An event as one line of text. -/
def printEvent (e : Event) : List Char := (ofEvent e).encode

/-- Read one line of a log. -/
def parseEvent (s : List Char) : Option Event := (Envelope.decode s).bind toEvent

/-- **A written line reads back as the same event.** -/
theorem parseEvent_printEvent {e : Event} (h : e.Wire) : parseEvent (printEvent e) = some e := by
  unfold parseEvent printEvent
  rw [Envelope.decode_encode, Option.bind_some, toEvent_ofEvent h]

/-! ## The log: bounded, ordered, and never losing the newest line -/

/-- The run so far: at most `cap` events, plus a count of what fell off
the front. -/
structure Log where
  /-- How many events are kept. -/
  cap : Nat
  /-- The events kept, oldest first. -/
  events : List Event
  /-- How many were dropped to stay inside `cap`. -/
  dropped : Nat
deriving DecidableEq, Repr

/-- An empty run. -/
def Log.empty (cap : Nat) : Log := ⟨cap, [], 0⟩

/-- How many events the run has produced, kept or dropped. -/
def Log.total (l : Log) : Nat := l.dropped + l.events.length

/-- Append an event, trimming the oldest lines if the log is full. -/
def Log.add (l : Log) (e : Event) : Log :=
  let es := l.events ++ [e]
  let excess := es.length - l.cap
  { cap := l.cap, events := es.drop excess, dropped := l.dropped + excess }

@[simp] theorem Log.add_cap (l : Log) (e : Event) : (l.add e).cap = l.cap := rfl

theorem Log.add_events_length (l : Log) (e : Event) :
    (l.add e).events.length = min (l.events.length + 1) l.cap := by
  simp only [Log.add, List.length_drop, List.length_append, List.length_cons,
    List.length_nil]
  omega

/-- **The log is bounded.**  However long the run, it holds at most `cap`
events. -/
theorem Log.add_length_le (l : Log) (e : Event) : (l.add e).events.length ≤ l.cap := by
  rw [Log.add_events_length]; omega

/-- **Nothing is uncounted.**  Every event is either held or counted in
`dropped`. -/
theorem Log.add_total (l : Log) (e : Event) : (l.add e).total = l.total + 1 := by
  simp only [Log.total, Log.add, List.length_drop, List.length_append, List.length_cons,
    List.length_nil]
  omega

/-- **The newest event is never the one dropped.**  Whatever went wrong a
moment ago is still in the log. -/
theorem Log.add_getLast (l : Log) (e : Event) (h : 1 ≤ l.cap) :
    (l.add e).events.getLast? = some e := by
  have hlen : l.events.length + 1 - l.cap ≤ l.events.length := by omega
  simp only [Log.add, List.length_append, List.length_cons, List.length_nil]
  rw [List.drop_append_of_le_length hlen]
  simp

/-- What an `add` keeps was either there before or is the new event. -/
theorem Log.add_mem {l : Log} {e x : Event} (hx : x ∈ (l.add e).events) :
    x ∈ l.events ∨ x = e := by
  have hsub : List.Sublist (l.add e).events (l.events ++ [e]) := by
    simpa [Log.add] using List.drop_sublist (l.events.length + 1 - l.cap) (l.events ++ [e])
  have := hsub.mem hx
  simpa using this

/-- A well-formed log: sequence numbers strictly increase, and every one
of them is below the number the next event will get. -/
def Log.Wf (l : Log) : Prop :=
  l.events.Pairwise (fun a b => a.seq < b.seq) ∧ ∀ e ∈ l.events, e.seq < l.total

theorem Log.wf_empty (cap : Nat) : (Log.empty cap).Wf := by
  constructor
  · simp [Log.empty]
  · intro e he; simp [Log.empty] at he

/-- Record an event, stamping it with the next sequence number. -/
def Log.record (l : Log) (ms : Nat) (lv : Level) (ar : Area) (text detail : List Char) : Log :=
  l.add ⟨l.total, ms, lv, ar, text, detail⟩

/-- **A recorded run stays in order**, and no sequence number is reused. -/
theorem Log.Wf.record {l : Log} (h : l.Wf) (ms : Nat) (lv : Level) (ar : Area)
    (text detail : List Char) : (l.record ms lv ar text detail).Wf := by
  set e : Event := ⟨l.total, ms, lv, ar, text, detail⟩ with he
  have hpair : (l.events ++ [e]).Pairwise (fun a b => a.seq < b.seq) := by
    refine List.pairwise_append.mpr ⟨h.1, List.pairwise_singleton _ _, ?_⟩
    intro a ha b hb
    simp only [List.mem_singleton] at hb
    subst hb
    exact h.2 a ha
  constructor
  · refine List.Pairwise.sublist ?_ hpair
    simpa [Log.record, Log.add] using
      List.drop_sublist (l.events.length + 1 - l.cap) (l.events ++ [e])
  · intro x hx
    have htot : (l.record ms lv ar text detail).total = l.total + 1 := Log.add_total l e
    rw [htot]
    rcases Log.add_mem hx with hx | hx
    · exact Nat.lt_succ_of_lt (h.2 x hx)
    · subst hx; simp

/-! ## Writing the whole run out, and reading it back -/

/-- Join lines with newlines. -/
def joinLines : List (List Char) → List Char
  | [] => []
  | [l] => l
  | l :: ls => l ++ '\n' :: joinLines ls

theorem newline_not_mem_hexEncode (bs : Blob) : '\n' ∉ hexEncode bs := by
  intro hmem
  simp only [hexEncode, List.mem_flatMap] at hmem
  obtain ⟨b, _, hcb⟩ := hmem
  have hb : b.toNat < 256 := b.toNat_lt_size
  have h1 : b.toNat / 16 < 16 := by omega
  have h2 : b.toNat % 16 < 16 := Nat.mod_lt _ (by norm_num)
  have hdig : ∀ n, n < 16 → hexDigit n ≠ '\n' := by
    intro n hn; interval_cases n <;> decide
  simp only [hexByte, List.mem_cons, List.not_mem_nil, or_false] at hcb
  rcases hcb with hcb | hcb
  · exact hdig _ h1 hcb.symm
  · exact hdig _ h2 hcb.symm

theorem newline_not_mem_joinFields {fs : List (List Char)} (h : ∀ f ∈ fs, '\n' ∉ f) :
    '\n' ∉ joinFields fs := by
  induction fs with
  | nil => simp [joinFields]
  | cons f fs ih =>
      cases fs with
      | nil => exact h f (by simp)
      | cons g gs =>
          rw [show joinFields (f :: g :: gs) = f ++ sep :: joinFields (g :: gs) from rfl]
          simp only [List.mem_append, List.mem_cons, not_or]
          exact ⟨h f (by simp), by decide, ih (fun x hx => h x (by simp [hx]))⟩

theorem newline_not_mem_encode (e : Envelope) : '\n' ∉ e.encode := by
  refine newline_not_mem_joinFields ?_
  intro f hf
  simp only [List.mem_map] at hf
  obtain ⟨b, _, rfl⟩ := hf
  exact newline_not_mem_hexEncode b

/-- A log line never contains a newline, so lines can be joined by one. -/
theorem newline_not_mem_printEvent (e : Event) : '\n' ∉ printEvent e :=
  newline_not_mem_encode _

theorem encode_ne_nil {e : Envelope} (h : e.tag ≠ []) : e.encode ≠ [] := by
  have hhex : hexEncode e.tag ≠ [] := by
    cases htag : e.tag with
    | nil => exact absurd htag h
    | cons b bs => simp [hexEncode, hexByte]
  unfold Envelope.encode
  cases hf : e.fields with
  | nil => simpa [joinFields] using hhex
  | cons g gs =>
      simp only [List.map_cons]
      rw [show joinFields (hexEncode e.tag :: hexEncode g :: gs.map hexEncode)
          = hexEncode e.tag ++ sep :: joinFields (hexEncode g :: gs.map hexEncode) from rfl]
      simp

/-- A written event is never the empty line. -/
theorem printEvent_ne_nil (e : Event) : printEvent e ≠ [] := by
  refine encode_ne_nil ?_
  simp [ofEvent, tagLog, asciiBytes]

theorem splitCh_joinLines {ls : List (List Char)} (hne : ls ≠ [])
    (h : ∀ l ∈ ls, '\n' ∉ l) : Kant.SiteCard.splitCh '\n' (joinLines ls) = ls := by
  induction ls with
  | nil => exact absurd rfl hne
  | cons f fs ih =>
      cases fs with
      | nil => exact Kant.SiteCard.splitCh_of_not_mem (h f (by simp))
      | cons g gs =>
          have hf : '\n' ∉ f := h f (by simp)
          have hrest : ∀ x ∈ g :: gs, '\n' ∉ x := fun x hx => h x (by simp [hx])
          rw [show joinLines (f :: g :: gs) = f ++ '\n' :: joinLines (g :: gs) from rfl,
            Kant.SiteCard.splitCh_append hf, ih (by simp) hrest]

/-- The run as text: one event per line. -/
def renderLog (l : Log) : List Char := joinLines (l.events.map printEvent)

/-- Read a list of log lines. -/
def parseEvents : List (List Char) → Option (List Event)
  | [] => some []
  | s :: ss =>
      match parseEvent s, parseEvents ss with
      | some e, some es => some (e :: es)
      | _, _ => none

theorem parseEvents_map {es : List Event} (h : ∀ e ∈ es, e.Wire) :
    parseEvents (es.map printEvent) = some es := by
  induction es with
  | nil => rfl
  | cons x xs ih =>
      simp only [List.map_cons, parseEvents, parseEvent_printEvent (h x (by simp)),
        ih (fun e he => h e (by simp [he]))]

/-- Read a whole run back. -/
def parseLog (s : List Char) : Option (List Event) :=
  if s = [] then some [] else parseEvents (Kant.SiteCard.splitCh '\n' s)

/-- **A shared run reads back exactly**, event for event, in order. -/
theorem parseLog_renderLog {l : Log} (h : ∀ e ∈ l.events, e.Wire) :
    parseLog (renderLog l) = some l.events := by
  cases hev : l.events with
  | nil => simp [parseLog, renderLog, hev, joinLines]
  | cons a as =>
      have hne : (l.events.map printEvent) ≠ [] := by simp [hev]
      have hnl : ∀ x ∈ l.events.map printEvent, '\n' ∉ x := by
        intro x hx
        simp only [List.mem_map] at hx
        obtain ⟨e, _, rfl⟩ := hx
        exact newline_not_mem_printEvent e
      have hsplit : Kant.SiteCard.splitCh '\n' (renderLog l) = l.events.map printEvent :=
        splitCh_joinLines hne hnl
      have hnonempty : renderLog l ≠ [] := by
        intro hz
        rw [hz] at hsplit
        rw [hev] at hsplit
        simp only [Kant.SiteCard.splitCh, List.map_cons] at hsplit
        exact printEvent_ne_nil a (by
          have := List.head_eq_of_cons_eq hsplit.symm
          simpa using this.symm)
      rw [parseLog, if_neg hnonempty, hsplit, parseEvents_map h, hev]

/-! ## Sharing a run without leaking the room -/

/-- Does this event quote `secret` anywhere? -/
def Event.mentions (secret : List Char) (e : Event) : Bool :=
  containsSub secret e.text || containsSub secret e.detail

/-- An event that quotes none of the secrets held. -/
def Event.clean (secrets : List (List Char)) (e : Event) : Bool :=
  secrets.all (fun s => !(e.mentions s))

/-- The run as it may be shared: every event that quotes a secret is
withheld. -/
def Log.share (secrets : List (List Char)) (l : Log) : Log :=
  { l with events := l.events.filter (Event.clean secrets) }

/-- **Nothing shared quotes a secret.** -/
theorem share_clean {secrets : List (List Char)} {l : Log} {e : Event}
    (h : e ∈ (l.share secrets).events) : e.clean secrets = true :=
  (List.mem_filter.mp h).2

/-- Spelt out: no secret occurs anywhere in a shared event, as sentence or
as detail. -/
theorem share_no_secret {secrets : List (List Char)} {l : Log} {e : Event}
    (he : e ∈ (l.share secrets).events) {s : List Char} (hs : s ∈ secrets) :
    ¬ (s <:+: e.text) ∧ ¬ (s <:+: e.detail) := by
  have hc := share_clean he
  simp only [Event.clean, List.all_eq_true, Bool.not_eq_true'] at hc
  have hmention := hc s hs
  simp only [Event.mentions, Bool.or_eq_false_iff] at hmention
  refine ⟨fun hinf => ?_, fun hinf => ?_⟩
  · have := (containsSub_iff_infix s e.text).mpr hinf
    rw [hmention.1] at this
    exact Bool.noConfusion this
  · have := (containsSub_iff_infix s e.detail).mpr hinf
    rw [hmention.2] at this
    exact Bool.noConfusion this

/-- **Nothing else is withheld**: an event that quotes no secret is shared
as it stands. -/
theorem share_keeps {secrets : List (List Char)} {l : Log} {e : Event}
    (he : e ∈ l.events) (hc : e.clean secrets = true) : e ∈ (l.share secrets).events :=
  List.mem_filter.mpr ⟨he, hc⟩

/-- A short, one-way handle for a room or a secret: eight hex characters
of its digest.  Safe to print, useless to a reader. -/
def ref (s : List Char) : List Char := (Kant.Bytes.witness (asciiBytes s)).take 8

@[simp] theorem ref_length (s : List Char) : (ref s).length = 8 := by
  simp [ref, Kant.Bytes.witness_length]

/-- The handle is not the thing: anything longer than eight characters
cannot be read out of it. -/
theorem ref_ne {s : List Char} (h : 8 < s.length) : ref s ≠ s := by
  intro hEq
  have := congrArg List.length hEq
  rw [ref_length] at this
  omega

/-! ## The report: the whole run, shareable -/

/-- What the diagnostics page hands over: the verdict, the room's handle,
the relay actually in use, and the run. -/
structure Report where
  /-- The verdict at the moment of sharing. -/
  verdict : Verdict
  /-- The room's eight-character handle, never the room itself. -/
  room : List Char
  /-- The relay in use, empty when there is none. -/
  relay : List Char
  /-- The events, already filtered by `Log.share`. -/
  events : List Event
deriving DecidableEq, Repr

/-- The wire code of a verdict. -/
def verdictCode : Verdict → UInt8
  | .ok => 1
  | .noRoom => 2
  | .roomMismatch => 3
  | .relayDown => 4
  | .onlyThisBrowser => 5
  | .noTransport => 6

/-- Read a verdict code. -/
def verdictOfCode : UInt8 → Option Verdict
  | 1 => some .ok
  | 2 => some .noRoom
  | 3 => some .roomMismatch
  | 4 => some .relayDown
  | 5 => some .onlyThisBrowser
  | 6 => some .noTransport
  | _ => none

@[simp] theorem verdictOfCode_code (v : Verdict) : verdictOfCode (verdictCode v) = some v := by
  cases v <;> rfl

/-- The tag of a report header. -/
def tagReport : Blob := asciiBytes "kzdiag".toList

/-- The header line of a report. -/
def header (r : Report) : List Char :=
  Envelope.encode
    { tag := tagReport, fields := [[verdictCode r.verdict], asciiBytes r.room, asciiBytes r.relay] }

/-- Read a header line. -/
def parseHeader (s : List Char) : Option (Verdict × List Char × List Char) :=
  match Envelope.decode s with
  | some e =>
      if e.tag ≠ tagReport then none else
        match e.fields with
        | [[vc], rm, rl] =>
            match verdictOfCode vc with
            | some v => some (v, asciiChars rm, asciiChars rl)
            | none => none
        | _ => none
  | none => none

/-- A report whose text travels unchanged. -/
structure Report.Wire (r : Report) : Prop where
  /-- The room handle is ASCII. -/
  room : IsAscii r.room
  /-- The relay URL is ASCII. -/
  relay : IsAscii r.relay
  /-- Every event is. -/
  events : ∀ e ∈ r.events, e.Wire

theorem parseHeader_header {r : Report} (h : r.Wire) :
    parseHeader (header r) = some (r.verdict, r.room, r.relay) := by
  unfold parseHeader header
  rw [Envelope.decode_encode]
  simp [asciiChars_asciiBytes h.room, asciiChars_asciiBytes h.relay]

/-- The report as text: the header, then the run, one event per line. -/
def renderReport (r : Report) : List Char := joinLines (header r :: r.events.map printEvent)

/-- Read a whole report back. -/
def parseReport (s : List Char) : Option Report :=
  match Kant.SiteCard.splitCh '\n' s with
  | [] => none
  | h :: rest =>
      match parseHeader h with
      | some (v, rm, rl) =>
          match parseEvents rest with
          | some es => some ⟨v, rm, rl, es⟩
          | none => none
      | none => none

theorem newline_not_mem_header (r : Report) : '\n' ∉ header r :=
  newline_not_mem_encode _

/-- **The whole run, shared, reads back as the same run.** -/
theorem parseReport_renderReport {r : Report} (h : r.Wire) :
    parseReport (renderReport r) = some r := by
  have hnl : ∀ x ∈ header r :: r.events.map printEvent, '\n' ∉ x := by
    intro x hx
    simp only [List.mem_cons, List.mem_map] at hx
    rcases hx with rfl | ⟨e, _, rfl⟩
    · exact newline_not_mem_header r
    · exact newline_not_mem_printEvent e
  have hsplit :
      Kant.SiteCard.splitCh '\n' (renderReport r) = header r :: r.events.map printEvent :=
    splitCh_joinLines (by simp) hnl
  unfold parseReport
  rw [hsplit]
  simp only [parseHeader_header h, parseEvents_map h.events]

/-- **Everything in a shared report has been through the filter.** -/
theorem report_events_clean {secrets : List (List Char)} {l : Log} {v : Verdict}
    {rm rl : List Char} {e : Event}
    (he : e ∈ (Report.mk v rm rl (l.share secrets).events).events) :
    e.clean secrets = true :=
  share_clean he

end Kant.Diagnostics
