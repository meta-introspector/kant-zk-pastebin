/-
# The command-line client, and the very same session in `curl`

The browser client is one program; an agent at a terminal is another.
This module is the specification both of them share, so that a session
driven from a shell — two clients, one relay, a link passed between them
through whatever chat window happens to be to hand — is *the same
session*, step for step, as the one in the page.

What is proved here:

* **The requests are curl.**  `curlArgv` prints the command line for a
  request, and `reqOfArgv` reads it back: `reqOfArgv_curlArgv` and
  `parseCurlLine_curlLine` say the printed command is exactly the request
  the client meant to make.  Nothing the client does is hidden from a
  terminal.
* **The relay answers a URL the way the browser answers a call.**
  `route` is the relay's router and `serve` its behaviour;
  `say_eq_browserSay` and `poll_eq_browserPoll` say that a client going
  over HTTP — the CLI, or curl by hand — lands in exactly the state the
  in-memory browser client lands in.  This is the "same results on the
  command line as in the browser" claim.
* **The page is static and the link carries everything.**
  `link_page_static` says the part of the link a static host ever sees is
  the site itself; `link_carries_invite` says the added information (the
  relay and the secret naming the room) rides in the fragment, and comes
  back out of it.  So a link pasted into Telegram, Discord or a tweet and
  opened by the other side names the same room: `join_same_room`,
  `join_same_relay`, `messy_join_same_room`.
* **Two clients find each other.**  `cliSession` is the whole run: A
  opens a room, the link travels through a chat, B joins it, A says
  something, B reads it, B answers, A reads it.  `cliSession_agree` says
  both sides end up holding the same two messages and displaying the same
  conversation, and `cliSession_room` that they were in one room all
  along.
* **The agent's command line.**  `parseArgv` / `printArgv` round-trip
  (`parseArgv_printArgv`), so every command the CLI offers can be written
  down, sent to somebody, and read back as the same command.

The JavaScript in `scripts/kant-cli.mjs` transcribes these definitions,
and `web/cli-test.mjs` checks it against the golden vectors at the end of
this file — as well as against a real relay, a real `curl`, and the
browser client itself.
-/
import Mathlib
import RequestProject.Kant.Join
import RequestProject.Kant.Relay
import RequestProject.Kant.Uucp

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.Cli

open Kant Kant.Bytes Kant.Text Kant.Clipboard Kant.Rendezvous Kant.Relay Kant.SiteCard Kant.Join

/-! ## Decimal numerals

A cursor travels in a query string, so it has to be written out and read
back; `digitsValue` (`Kant.Text`) reads, and `decNum` writes. -/

/-- The character of a decimal digit. -/
def digitChar (k : Nat) : Char := Char.ofNat (48 + k)

theorem digitChar_isDigit {k : Nat} (h : k < 10) : '0' ≤ digitChar k ∧ digitChar k ≤ '9' := by
  interval_cases k <;> decide

theorem digitChar_toNat {k : Nat} (h : k < 10) : (digitChar k).toNat - 48 = k := by
  interval_cases k <;> decide

/-- Decimal digits, most significant first; `fuel` bounds the recursion. -/
def decAux : Nat → Nat → List Char
  | 0, _ => []
  | fuel + 1, n => if n < 10 then [digitChar n] else decAux fuel (n / 10) ++ [digitChar (n % 10)]

/-- A number written out in decimal. -/
def decNum (n : Nat) : List Char := decAux (n + 1) n

/-- One step of `digitsValue`. -/
theorem digitsValue_append (a b : List Char) :
    digitsValue (a ++ b) =
      b.foldl (fun acc c => if '0' ≤ c ∧ c ≤ '9' then acc * 10 + (c.toNat - 48) else acc)
        (digitsValue a) := by
  simp [digitsValue, List.foldl_append]

theorem digitsValue_append_digit {a : List Char} {k : Nat} (h : k < 10) :
    digitsValue (a ++ [digitChar k]) = digitsValue a * 10 + k := by
  rw [digitsValue_append]
  simp only [List.foldl_cons, List.foldl_nil]
  rw [if_pos (digitChar_isDigit h), digitChar_toNat h]

theorem digitsValue_decAux : ∀ fuel n : Nat, n < fuel → digitsValue (decAux fuel n) = n := by
  intro fuel
  induction fuel with
  | zero => intro n h; exact absurd h (by omega)
  | succ f ih =>
      intro n hn
      rw [decAux]
      by_cases h : n < 10
      · rw [if_pos h]
        have := digitsValue_append_digit (a := ([] : List Char)) h
        simpa [digitsValue] using this
      · rw [if_neg h]
        have hlt : n / 10 < f := by
          have : n / 10 < n := Nat.div_lt_self (by omega) (by omega)
          omega
        rw [digitsValue_append_digit (Nat.mod_lt _ (by norm_num)), ih _ hlt]
        omega

/-- **A cursor written out is the cursor read back.** -/
@[simp] theorem digitsValue_decNum (n : Nat) : digitsValue (decNum n) = n :=
  digitsValue_decAux (n + 1) n (by omega)

/-! ## Words on a command line -/

/-- Join words with single spaces. -/
def joinSp : List (List Char) → List Char
  | [] => []
  | [w] => w
  | w :: ws => w ++ ' ' :: joinSp ws

/-- **A command line splits back into its words**, as long as no word
contains a space — and none of ours does: every code in this system is
hex and colons. -/
theorem splitCh_joinSp : ∀ {ws : List (List Char)}, ws ≠ [] → (∀ w ∈ ws, ' ' ∉ w) →
    splitCh ' ' (joinSp ws) = ws := by
  intro ws
  induction ws with
  | nil => intro h _; exact absurd rfl h
  | cons w ws ih =>
      intro _ hsp
      cases ws with
      | nil => exact splitCh_of_not_mem (hsp w (by simp))
      | cons v vs =>
          have hw : ' ' ∉ w := hsp w (by simp)
          have hrest : ∀ x ∈ v :: vs, ' ' ∉ x := fun x hx => hsp x (by simp [hx])
          rw [show joinSp (w :: v :: vs) = w ++ ' ' :: joinSp (v :: vs) from rfl,
            splitCh_append hw, ih (by simp) hrest]

/-! ## Requests, and the `curl` that makes them -/

/-- The two methods the relay understands. -/
inductive Method
  /-- Read a room. -/
  | get
  /-- Append to a room. -/
  | post
deriving DecidableEq, Repr

/-- One HTTP request. -/
structure Req where
  /-- `GET` or `POST`. -/
  method : Method
  /-- The whole URL, relay included. -/
  url : List Char
  /-- The body, empty for a `GET`. -/
  body : List Char
deriving DecidableEq, Repr

/-- A read. -/
def getReq (url : List Char) : Req := ⟨.get, url, []⟩

/-- A write. -/
def postReq (url body : List Char) : Req := ⟨.post, url, body⟩

/-- The `curl` command line for a request, as a list of arguments. -/
def curlArgv : Req → List (List Char)
  | ⟨.get, url, _⟩ => ["curl".toList, "-sS".toList, url]
  | ⟨.post, url, body⟩ =>
      ["curl".toList, "-sS".toList, "-X".toList, "POST".toList, "-H".toList,
        "content-type:text/plain".toList, "--data-binary".toList, body, url]

/-- Read a `curl` command line back as the request it makes. -/
def reqOfArgv : List (List Char) → Option Req
  | [c, f, url] =>
      if c = "curl".toList ∧ f = "-sS".toList then some (getReq url) else none
  | [c, f, x, p, h, ct, d, body, url] =>
      if c = "curl".toList ∧ f = "-sS".toList ∧ x = "-X".toList ∧ p = "POST".toList ∧
          h = "-H".toList ∧ ct = "content-type:text/plain".toList ∧
          d = "--data-binary".toList then
        some (postReq url body)
      else none
  | _ => none

/-- **The printed command is the request.**  Whatever the client is
about to do, the line it prints for you to run does exactly that. -/
theorem reqOfArgv_curlArgv (r : Req) (h : r.method = Method.get → r.body = []) :
    reqOfArgv (curlArgv r) = some r := by
  obtain ⟨m, u, b⟩ := r
  cases m with
  | get =>
      have hb : b = [] := h rfl
      subst hb
      simp [curlArgv, reqOfArgv, getReq]
  | post => simp [curlArgv, reqOfArgv, postReq]

/-- The command line as one string. -/
def curlLine (r : Req) : List Char := joinSp (curlArgv r)

/-- Read a command line back. -/
def parseCurlLine (s : List Char) : Option Req := reqOfArgv (splitCh ' ' s)

theorem curlArgv_ne_nil (r : Req) : curlArgv r ≠ [] := by
  obtain ⟨m, u, b⟩ := r; cases m <;> simp [curlArgv]

theorem curlArgv_spaceFree {r : Req} (hu : ' ' ∉ r.url) (hb : ' ' ∉ r.body) :
    ∀ w ∈ curlArgv r, ' ' ∉ w := by
  obtain ⟨m, u, b⟩ := r
  cases m <;> intro w hw <;>
    · simp only [curlArgv, List.mem_cons, List.not_mem_nil, or_false] at hw
      rcases hw with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
        first
          | decide
          | exact hu
          | exact hb

/-- **The command line, written out and read back, is the same
request.** -/
theorem parseCurlLine_curlLine {r : Req} (hu : ' ' ∉ r.url) (hb : ' ' ∉ r.body)
    (h : r.method = Method.get → r.body = []) : parseCurlLine (curlLine r) = some r := by
  unfold parseCurlLine curlLine
  rw [splitCh_joinSp (curlArgv_ne_nil r) (curlArgv_spaceFree hu hb)]
  exact reqOfArgv_curlArgv r h

/-! ## The relay's routes

`server/relay.mjs` serves exactly two paths that matter: a room, and a
room from a cursor.  Here they are, and here is the router. -/

/-- The path of a room. -/
def roomPath (room : List Char) : List Char := "/room/".toList ++ room

/-- The query string that asks for everything after a cursor. -/
def cursorQuery (cursor : Nat) : List Char := "?cursor=".toList ++ decNum cursor

/-- What a request names: a room, and where in it to start. -/
structure Route where
  /-- The room. -/
  room : List Char
  /-- The cursor, `0` when the request carries none. -/
  cursor : Nat
deriving DecidableEq, Repr

/-- Strip a known prefix. -/
def afterPrefix (p s : List Char) : Option (List Char) :=
  if p.isPrefixOf s then some (s.drop p.length) else none

@[simp] theorem afterPrefix_append (p s : List Char) : afterPrefix p (p ++ s) = some s := by
  simp [afterPrefix, List.isPrefixOf_iff_prefix]

/-- The relay's router. -/
def route (path : List Char) : Option Route :=
  match afterPrefix "/room/".toList path with
  | none => none
  | some rest =>
      match breakAt '?' rest with
      | none => some ⟨rest, 0⟩
      | some (room, q) => some ⟨room, digitsValue q⟩

theorem breakAt_eq_none_of_not_mem {d : Char} {s : List Char} (h : d ∉ s) :
    breakAt d s = none := by
  induction s with
  | nil => rfl
  | cons c cs ih =>
      have hc : c ≠ d := fun hc => h (by simp [hc])
      have hrest : d ∉ cs := fun hx => h (by simp [hx])
      simp [breakAt, hc, ih hrest]

theorem route_roomPath {room : List Char} (h : '?' ∉ room) :
    route (roomPath room) = some ⟨room, 0⟩ := by
  simp [route, roomPath, afterPrefix_append, breakAt_eq_none_of_not_mem h]

theorem digitsValue_cursorQueryTail (cursor : Nat) :
    digitsValue ("cursor=".toList ++ decNum cursor) = cursor := by
  rw [digitsValue_append, show digitsValue "cursor=".toList = 0 from by decide]
  exact digitsValue_decNum cursor

theorem route_pollPath {room : List Char} (h : '?' ∉ room) (cursor : Nat) :
    route (roomPath room ++ cursorQuery cursor) = some ⟨room, cursor⟩ := by
  have hsplit : roomPath room ++ cursorQuery cursor
      = "/room/".toList ++ (room ++ '?' :: ("cursor=".toList ++ decNum cursor)) := by
    rw [roomPath, cursorQuery, List.append_assoc]
    rfl
  rw [hsplit]
  simp [route, afterPrefix_append, breakAt_append h, digitsValue_cursorQueryTail]

/-! ## What the relay does with a request -/

/-- What the relay answers with. -/
structure Resp where
  /-- The lines it hands over. -/
  lines : List (List Char)
  /-- Where the room now ends. -/
  cursor : Nat
deriving DecidableEq, Repr

/-- The relay, serving one request that arrived at `base`. -/
def serve (sv : Server) (base : List Char) (r : Req) : Server × Resp :=
  match (afterPrefix base r.url).bind route with
  | none => (sv, ⟨[], 0⟩)
  | some rt =>
      match r.method with
      | .post =>
          let sv' := sv.post rt.room r.body
          (sv', ⟨[], (sv'.lines rt.room).length⟩)
      | .get => (sv, ⟨(sv.fetch rt.room rt.cursor).1, (sv.fetch rt.room rt.cursor).2⟩)

/-! ## The client

Everything an agent's client holds between commands, and what it puts on
the wire. -/

/-- One command-line client's whole state; `scripts/kant-cli.mjs` keeps
exactly this in its state file. -/
structure Client where
  /-- This client's peer identifier. -/
  self : List Char
  /-- The relay it uses, as an absolute URL. -/
  relay : List Char
  /-- The room secret; the room is its digest. -/
  secret : Blob
  /-- Its own message counter. -/
  seq : Nat
  /-- How far it has read the room. -/
  cursor : Nat
  /-- The messages it holds. -/
  messages : List Msg
deriving DecidableEq, Repr

/-- The room a client is in. -/
def Client.room (c : Client) : List Char := roomOf c.secret

/-- The conversation it displays. -/
def Client.view (c : Client) : List Msg := transcript c.messages

/-- A room name is hex, so it never carries a `'?'` and never confuses a
query string. -/
theorem question_not_mem_roomOf (s : Blob) : '?' ∉ roomOf s := by
  intro hmem
  have := mem_hexEncode_isCodeChar (bs := digest s) hmem
  exact absurd this (by decide)

/-- The request that posts a line. -/
def postLine (c : Client) (line : List Char) : Req :=
  postReq (c.relay ++ roomPath c.room) line

/-- The request that reads everything new. -/
def pollFrom (c : Client) : Req :=
  getReq (c.relay ++ (roomPath c.room ++ cursorQuery c.cursor))

/-- The message a client is about to write. -/
def Client.compose (c : Client) (body : Blob) : Msg := ⟨c.room, c.self, c.seq + 1, body⟩

/-- **Saying something, over HTTP.** -/
def say (sv : Server) (c : Client) (body : Blob) : Server × Client :=
  let line := printMsg (c.compose body)
  let out := serve sv c.relay (postLine c line)
  (out.1, { c with seq := c.seq + 1, messages := accept c.messages line })

/-- **Reading the room, over HTTP.** -/
def poll (sv : Server) (c : Client) : Server × Client :=
  let out := serve sv c.relay (pollFrom c)
  (out.1, { c with cursor := out.2.cursor, messages := receive c.messages out.2.lines })

/-- The same, as the browser client does it: straight against the relay
semantics, with no URL in sight (`Kant.Relay.Server`). -/
def browserSay (sv : Server) (c : Client) (body : Blob) : Server × Client :=
  let line := printMsg (c.compose body)
  (sv.post c.room line, { c with seq := c.seq + 1, messages := accept c.messages line })

/-- The browser's poll. -/
def browserPoll (sv : Server) (c : Client) : Server × Client :=
  let f := sv.fetch c.room c.cursor
  (sv, { c with cursor := f.2, messages := receive c.messages f.1 })

/-- **The command line says exactly what the browser says.**  The URL the
CLI builds, routed by the relay, is the very same append. -/
theorem say_eq_browserSay (sv : Server) (c : Client) (body : Blob) :
    say sv c body = browserSay sv c body := by
  simp [say, browserSay, serve, postLine, postReq, afterPrefix_append,
    route_roomPath (question_not_mem_roomOf c.secret), Client.room]

/-- **And hears exactly what the browser hears.** -/
theorem poll_eq_browserPoll (sv : Server) (c : Client) :
    poll sv c = browserPoll sv c := by
  simp [poll, browserPoll, serve, pollFrom, getReq, afterPrefix_append,
    route_pollPath (question_not_mem_roomOf c.secret), Client.room]

/-! ## Every step of a session can be typed into a terminal

Nothing in a room name, a cursor or a chat line is a space, so each
request the client makes prints as one `curl` command and reads back as
the request it was. -/

theorem mem_decAux {c : Char} : ∀ (fuel n : Nat), c ∈ decAux fuel n → ∃ k, k < 10 ∧ c = digitChar k := by
  intro fuel
  induction fuel with
  | zero => intro n h; simp [decAux] at h
  | succ f ih =>
      intro n h
      rw [decAux] at h
      by_cases hn : n < 10
      · rw [if_pos hn] at h
        rcases List.mem_singleton.mp h with rfl
        exact ⟨n, hn, rfl⟩
      · rw [if_neg hn] at h
        rcases List.mem_append.mp h with h | h
        · exact ih _ h
        · rcases List.mem_singleton.mp h with rfl
          exact ⟨n % 10, Nat.mod_lt _ (by norm_num), rfl⟩

theorem space_not_mem_decNum (n : Nat) : ' ' ∉ decNum n := by
  intro h
  obtain ⟨k, hk, hc⟩ := mem_decAux (n + 1) n h
  interval_cases k <;> exact absurd hc (by decide)

theorem space_not_mem_roomOf (s : Blob) : ' ' ∉ roomOf s := by
  intro hmem
  have := mem_hexEncode_isCodeChar (bs := digest s) hmem
  exact absurd this (by decide)

theorem space_not_mem_printMsg (m : Msg) : ' ' ∉ printMsg m := by
  intro hmem
  have := allCode_encode (ofMsg m) ' ' hmem
  exact absurd this (by decide)

theorem space_not_mem_roomPath {room : List Char} (h : ' ' ∉ room) : ' ' ∉ roomPath room := by
  intro hmem
  rcases List.mem_append.mp hmem with hc | hc
  · exact absurd hc (by decide)
  · exact h hc

/-- **Posting a line is one `curl` command.** -/
theorem postLine_curl_roundTrip {c : Client} {line : List Char} (hr : ' ' ∉ c.relay)
    (hl : ' ' ∉ line) : parseCurlLine (curlLine (postLine c line)) = some (postLine c line) := by
  refine parseCurlLine_curlLine ?_ hl (by simp [postLine, postReq])
  intro hmem
  rcases List.mem_append.mp hmem with hc | hc
  · exact hr hc
  · exact space_not_mem_roomPath (space_not_mem_roomOf c.secret) hc

/-- **Saying something is one `curl` command.** -/
theorem say_curl_roundTrip {c : Client} {body : Blob} (hr : ' ' ∉ c.relay) :
    parseCurlLine (curlLine (postLine c (printMsg (c.compose body))))
      = some (postLine c (printMsg (c.compose body))) :=
  postLine_curl_roundTrip hr (space_not_mem_printMsg _)

/-- **Reading the room is one `curl` command.** -/
theorem pollFrom_curl_roundTrip {c : Client} (hr : ' ' ∉ c.relay) :
    parseCurlLine (curlLine (pollFrom c)) = some (pollFrom c) := by
  refine parseCurlLine_curlLine ?_ (by simp [pollFrom, getReq]) (by simp [pollFrom, getReq])
  intro hmem
  simp only [pollFrom, getReq, List.mem_append] at hmem
  rcases hmem with hc | hc | hc
  · exact hr hc
  · exact space_not_mem_roomPath (space_not_mem_roomOf c.secret) hc
  · rcases List.mem_append.mp hc with hc | hc
    · exact absurd hc (by decide)
    · exact space_not_mem_decNum c.cursor hc

/-! ## Opening a room, and joining one from a link -/

/-- A brand new client holding a brand new room. -/
def openRoom (self relay : List Char) (secret : Blob) : Client := ⟨self, relay, secret, 0, 0, []⟩

/-- The invitation this client hands out. -/
def Client.invite (c : Client) : Invite := ⟨c.relay, c.secret, c.self, []⟩

/-- The link it prints: the site, and the invitation in the fragment. -/
def Client.link (cfg : Config) (c : Client) : List Char :=
  Kant.InviteCard.inviteUrl cfg c.invite

/-- Everything before the `'#'`: all a static host ever sees. -/
def pageOf : List Char → List Char
  | [] => []
  | c :: cs => if c = Kant.Clipboard.hash then [] else c :: pageOf cs

theorem pageOf_append {base rest : List Char} (h : Kant.Clipboard.hash ∉ base) :
    pageOf (base ++ Kant.Clipboard.hash :: rest) = base := by
  induction base with
  | nil => simp [pageOf]
  | cons c cs ih =>
      have hc : c ≠ Kant.Clipboard.hash := fun hc => h (by simp [hc])
      have hrest : Kant.Clipboard.hash ∉ cs := fun hx => h (by simp [hx])
      rw [List.cons_append, pageOf, if_neg hc, ih hrest]

/-- **The page is static.**  The link two agents pass to each other asks
the host for nothing but the site itself; everything they add to it is in
the fragment, which never leaves the client. -/
theorem link_page_static {cfg : Config} (h : Kant.Clipboard.hash ∉ cfg.origin) (c : Client) :
    pageOf (c.link cfg) = cfg.origin := by
  rw [Client.link, Kant.InviteCard.inviteUrl_eq]
  exact pageOf_append h

/-- **And the link carries the room.** -/
theorem link_carries_invite {cfg : Config} (h : Kant.Clipboard.hash ∉ cfg.origin) {c : Client}
    (hw : c.invite.Wire) : Kant.Rendezvous.parseInviteUrl (c.link cfg) = some c.invite :=
  Kant.Rendezvous.parseInviteUrl_inviteUrl h hw

/-- Join whatever room a pasted message names. -/
def joinText (self : List Char) (text : List Char) : Option Client :=
  (findInvite text).map fun i => ⟨self, i.relay, i.secret, 0, 0, []⟩

/-- **Loading the link joins the room.** -/
theorem joinText_link {cfg : Config} (ho : BlankFree cfg.origin) {c : Client}
    (hw : c.invite.Wire) (self : List Char) :
    joinText self (c.link cfg) = some ⟨self, c.relay, c.secret, 0, 0, []⟩ := by
  unfold joinText Client.link
  rw [findInvite_inviteUrl ho hw]
  rfl

/-- **The other agent lands in the same room.** -/
theorem join_same_room {cfg : Config} (ho : BlankFree cfg.origin) {c : Client}
    (hw : c.invite.Wire) (self : List Char) :
    (joinText self (c.link cfg)).map Client.room = some c.room := by
  rw [joinText_link ho hw]
  rfl

/-- **…and on the same relay.** -/
theorem join_same_relay {cfg : Config} (ho : BlankFree cfg.origin) {c : Client}
    (hw : c.invite.Wire) (self : List Char) :
    (joinText self (c.link cfg)).map Client.relay = some c.relay := by
  rw [joinText_link ho hw]
  rfl

/-- **However the chat mangles it.**  Text before the link, text after
it, a bracket in front and a full stop behind: the agent that pastes the
message still lands in the room the link named. -/
theorem messy_join_same_room {cfg : Config} (ho : BlankFree cfg.origin) {c : Client}
    (hw : c.invite.Wire) (self : List Char) {before after lead trail : List Char}
    (hbefore : findInvite before = none) (hlead : BlankFree lead) (htrailB : BlankFree trail)
    (hhash : Kant.Clipboard.hash ∉ trail) (htrail : NoCode trail)
    {sp sq : Char} (hsp : isBlank sp = true) (hsq : isBlank sq = true) :
    (joinText self (before ++ sp :: ((lead ++ c.link cfg ++ trail) ++ sq :: after))).map
      Client.room = some c.room := by
  unfold joinText Client.link
  rw [findInvite_in_message ho hw hbefore hlead htrailB hhash htrail hsp hsq]
  rfl

/-! ## Loading a URL

The agents' channel carries links, and a link points at the static page
with the information added after the `'#'`.  Two kinds of information go
there: an invitation (a room to meet in) and a mailbag (a conversation
carried whole, with no relay at all, `Kant.Uucp`).  Loading a URL is
deciding which of them it is. -/

/-- What a URL turns out to carry. -/
inductive Loaded
  /-- A room to join. -/
  | invitation (i : Invite)
  /-- A conversation, carried in the link itself. -/
  | bag (ms : List Msg)
  /-- Nothing this client can use. -/
  | nothing
deriving Repr

/-- **Load a URL.** -/
def loadUrl (u : List Char) : Loaded :=
  match findInvite u with
  | some i => .invitation i
  | none =>
      match Kant.Uucp.readBagUrl u with
      | some ms => .bag ms
      | none => .nothing

/-- **An invite link loads as the room it names.** -/
theorem loadUrl_link {cfg : Config} (ho : BlankFree cfg.origin) {c : Client}
    (hw : c.invite.Wire) : loadUrl (c.link cfg) = .invitation c.invite := by
  unfold loadUrl Client.link
  rw [findInvite_inviteUrl ho hw]

/-- An envelope with a tag prints as something. -/
theorem encode_ne_nil {e : Envelope} (ht : e.tag ≠ []) : e.encode ≠ [] := by
  intro h
  have hd : Envelope.decode e.encode = some e := Envelope.decode_encode e
  rw [h, show Envelope.decode ([] : List Char) = some ⟨[], []⟩ from rfl] at hd
  exact ht (congrArg Envelope.tag (Option.some.injEq _ _ ▸ hd)).symm

/-- A mailbag link names no room: it is a conversation, not an
invitation. -/
theorem findInvite_bagUrl {base : List Char} (ho : BlankFree base) (ms : List Msg) :
    findInvite (Kant.Uucp.bagUrl base ms) = none := by
  have htag : (Kant.Uucp.ofBag ms).tag ≠ tagInvite := by
    show Kant.Uucp.tagBag ≠ tagInvite
    decide
  have htne : (Kant.Uucp.ofBag ms).tag ≠ [] := by
    show Kant.Uucp.tagBag ≠ []
    decide
  have hsplit : Kant.Uucp.bagUrl base ms
      = base ++ Kant.Clipboard.hash :: ((Kant.Uucp.ofBag ms).encode ++ []) := by
    simp [Kant.Uucp.bagUrl, Kant.Clipboard.shareUrl]
  have hcode : AllCode ((Kant.Uucp.ofBag ms).encode) := allCode_encode _
  have hblank : BlankFree (Kant.Uucp.bagUrl base ms) := by
    rw [hsplit]
    intro ch hch
    simp only [List.mem_append, List.mem_cons, List.append_nil] at hch
    rcases hch with hch | rfl | hch
    · exact ho ch hch
    · decide
    · exact isCodeChar_not_blank (hcode ch hch)
  have hne : Kant.Uucp.bagUrl base ms ≠ [] := by
    rw [hsplit]
    intro h
    have := congrArg List.length h
    simp at this
  rw [findInvite_of_word hblank hne, wordInvite, hsplit,
    codePart_junk hcode (encode_ne_nil htne) (by simp) (by intro x hx; simp at hx)]
  unfold pasteInvite
  rw [Envelope.decode_encode]
  simp [toInvite, htag]

/-- **A mailbag link loads as the conversation it carries** — with no
relay, and nothing asked of the host but the page. -/
theorem loadUrl_bagUrl {base : List Char} (ho : BlankFree base)
    (hb : Kant.Clipboard.hash ∉ base) {ms : List Msg} (hw : ∀ m ∈ ms, m.Wire) :
    loadUrl (Kant.Uucp.bagUrl base ms) = .bag ms := by
  unfold loadUrl
  rw [findInvite_bagUrl ho ms, Kant.Uucp.readBagUrl_bagUrl hb hw]

/-! ## Two agents, one relay, one link: the whole run -/

/-- The four moves after the link has been passed: A says something, B
reads it, B answers, A reads that. -/
def meet (sv : Server) (host guest : Client) (ta tb : Blob) : Server × Client × Client :=
  let s1 := say sv host ta
  let s2 := poll s1.1 guest
  let s3 := say s2.1 s2.2 tb
  let s4 := poll s3.1 s1.2
  (s4.1, s4.2, s3.2)

/-- The whole session, from an empty relay: A opens a room, the link
travels through some chat window as `pasted`, B joins it, and the two of
them talk. -/
def cliSession (relay : List Char) (secret : Blob) (a b : List Char) (pasted : List Char)
    (ta tb : Blob) : Option (Server × Client × Client) :=
  let host := openRoom a relay secret
  (joinText b pasted).map fun guest => meet Server.empty host guest ta tb

theorem accept_printMsg_of_not_mem {ms : List Msg} {m : Msg} (hw : m.Wire) (h : m ∉ ms) :
    accept ms (printMsg m) = m :: ms := by
  unfold accept
  rw [parseMsg_printMsg hw]
  simp [h]

theorem accept_printMsg_of_mem {ms : List Msg} {m : Msg} (hw : m.Wire) (h : m ∈ ms) :
    accept ms (printMsg m) = ms := by
  unfold accept
  rw [parseMsg_printMsg hw]
  simp [h]

/-- The four moves, worked out.  Two fresh clients in one room: A's line
reaches B, B's answer reaches A, and both sides end up holding the two
messages in the same order. -/
theorem meet_fresh {relay : List Char} {secret : Blob} {a b : List Char} {ta tb : Blob}
    (hwa : (Msg.mk (roomOf secret) a 1 ta).Wire) (hwb : (Msg.mk (roomOf secret) b 1 tb).Wire)
    (hab : a ≠ b) :
    meet Server.empty (openRoom a relay secret) (openRoom b relay secret) ta tb
      = ((Server.empty.post (roomOf secret) (printMsg ⟨roomOf secret, a, 1, ta⟩)).post
            (roomOf secret) (printMsg ⟨roomOf secret, b, 1, tb⟩),
          ⟨a, relay, secret, 1, 2,
            [⟨roomOf secret, b, 1, tb⟩, ⟨roomOf secret, a, 1, ta⟩]⟩,
          ⟨b, relay, secret, 1, 1,
            [⟨roomOf secret, b, 1, tb⟩, ⟨roomOf secret, a, 1, ta⟩]⟩) := by
  classical
  have hne : (Msg.mk (roomOf secret) b 1 tb) ≠ (Msg.mk (roomOf secret) a 1 ta) := by
    intro h
    exact hab (congrArg Msg.sender h).symm
  have h1 : accept [] (printMsg ⟨roomOf secret, a, 1, ta⟩) = [⟨roomOf secret, a, 1, ta⟩] :=
    accept_printMsg_of_not_mem hwa (by simp)
  have h2 : accept [(⟨roomOf secret, a, 1, ta⟩ : Msg)]
      (printMsg ⟨roomOf secret, a, 1, ta⟩) = [⟨roomOf secret, a, 1, ta⟩] :=
    accept_printMsg_of_mem hwa (by simp)
  have h3 : accept [(⟨roomOf secret, a, 1, ta⟩ : Msg)] (printMsg ⟨roomOf secret, b, 1, tb⟩)
      = [⟨roomOf secret, b, 1, tb⟩, ⟨roomOf secret, a, 1, ta⟩] :=
    accept_printMsg_of_not_mem hwb (by simp [hne])
  simp only [meet, say_eq_browserSay, poll_eq_browserPoll, browserSay, browserPoll, openRoom,
    Client.compose, Client.room, Server.fetch, Server.lines_post, Server.lines_empty,
    List.nil_append, List.drop_zero, receive, List.foldl_append, List.foldl_cons, List.foldl_nil,
    List.length_append, List.length_cons, List.length_nil, Nat.zero_add, h1]
  rw [h2, h3]

/-- **Two command-line clients find each other and talk.**  Given only a
link passed through some chat window, both sides end up holding both
messages, and both display the same conversation. -/
theorem cliSession_agree {relay : List Char} {secret : Blob} {a b : List Char}
    {pasted : List Char} {ta tb : Blob}
    (hpaste : findInvite pasted = some (openRoom a relay secret).invite)
    (hwa : (Msg.mk (roomOf secret) a 1 ta).Wire) (hwb : (Msg.mk (roomOf secret) b 1 tb).Wire)
    (hab : a ≠ b) :
    ∃ sv host' guest',
      cliSession relay secret a b pasted ta tb = some (sv, host', guest') ∧
      host'.messages = [⟨roomOf secret, b, 1, tb⟩, ⟨roomOf secret, a, 1, ta⟩] ∧
      guest'.messages = host'.messages ∧
      host'.room = guest'.room ∧
      host'.view = guest'.view := by
  have hguest : joinText b pasted = some (openRoom b relay secret) := by
    unfold joinText
    rw [hpaste]
    rfl
  have hsession : cliSession relay secret a b pasted ta tb
      = some (meet Server.empty (openRoom a relay secret) (openRoom b relay secret) ta tb) := by
    unfold cliSession
    rw [hguest]
    rfl
  rw [hsession, meet_fresh hwa hwb hab]
  exact ⟨_, _, _, rfl, rfl, rfl, rfl, rfl⟩

/-! ## The agent's command line -/

/-- The commands `scripts/kant-cli.mjs` offers. -/
inductive Cmd
  /-- Open a fresh room on a relay. -/
  | «open» (relay : List Char)
  /-- Print the link to hand to the other agent. -/
  | link
  /-- Print the room. -/
  | room
  /-- Join the room named by a pasted message. -/
  | join (text : List Char)
  /-- Say something. -/
  | say (text : List Char)
  /-- Read the room and print the conversation. -/
  | read
  /-- Print the `curl` command lines instead of making the requests. -/
  | curl
deriving DecidableEq, Repr

/-- The command as an argument list. -/
def printArgv : Cmd → List (List Char)
  | .open relay => ["open".toList, relay]
  | .link => ["link".toList]
  | .room => ["room".toList]
  | .join text => ["join".toList, text]
  | .say text => ["say".toList, text]
  | .read => ["read".toList]
  | .curl => ["curl".toList]

/-- Read an argument list as a command. -/
def parseArgv : List (List Char) → Option Cmd
  | [w] =>
      if w = "link".toList then some .link
      else if w = "room".toList then some .room
      else if w = "read".toList then some .read
      else if w = "curl".toList then some .curl
      else none
  | [w, x] =>
      if w = "open".toList then some (.open x)
      else if w = "join".toList then some (.join x)
      else if w = "say".toList then some (.say x)
      else none
  | _ => none

/-- **Every command can be written down and read back.** -/
theorem parseArgv_printArgv (c : Cmd) : parseArgv (printArgv c) = some c := by
  cases c <;> simp +decide [printArgv, parseArgv]

/-! ## Golden vectors shared with the JavaScript -/

section Guards

private def guardSecret : Blob := asciiBytes "swordfish".toList

private def guardRoom : List Char := roomOf guardSecret

private def guardClient : Client := openRoom "agent-a".toList "http://127.0.0.1:8787".toList
  guardSecret

#guard decNum 0 = "0".toList
#guard decNum 7 = "7".toList
#guard decNum 1024 = "1024".toList
#guard digitsValue (decNum 90210) = 90210
#guard roomPath guardRoom = "/room/".toList ++ guardRoom
#guard cursorQuery 3 = "?cursor=3".toList
#guard route (roomPath guardRoom) = some ⟨guardRoom, 0⟩
#guard route (roomPath guardRoom ++ cursorQuery 12) = some ⟨guardRoom, 12⟩
#guard (pollFrom guardClient).url =
  "http://127.0.0.1:8787".toList ++ ("/room/".toList ++ guardRoom ++ "?cursor=0".toList)
#guard curlLine (getReq "http://x/health".toList) = "curl -sS http://x/health".toList
#guard curlLine (postReq "http://x/room/r".toList "abc".toList) =
  "curl -sS -X POST -H content-type:text/plain --data-binary abc http://x/room/r".toList
#guard parseCurlLine (curlLine (postReq "http://x/room/r".toList "abc".toList)) =
  some (postReq "http://x/room/r".toList "abc".toList)
#guard parseArgv (printArgv (Cmd.say "hello".toList)) = some (Cmd.say "hello".toList)
#guard pageOf "https://kant.example/#kzinvite".toList = "https://kant.example/".toList
#guard (match loadUrl (Kant.Uucp.bagUrl "https://kant.example/".toList []) with
  | .bag ms => ms.length = 0
  | _ => false)
#guard (openRoom "agent-a".toList "http://r".toList guardSecret).room = guardRoom

end Guards

end Kant.Cli
