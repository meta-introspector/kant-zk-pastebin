/-
# Executable demonstration of the ported pipeline

Everything in the port is computable, so the whole flow can be run.  The
`#guard` commands below are checked when this file is compiled: if any of
them evaluated to `false` the build would fail.  They exercise

* content addressing (witness width, DASL address type and prefix),
* orbifold coordinates and the Monster tables,
* eRDFa escaping,
* framing under a channel cap and reassembly from shuffled frames,
* LSB steganography in a carrier image,
* the credit ledger,
* Gödel numbering of a code movie and of a circuit,
* the relay-free sneakernet: mailbags, tweet threads, bang paths and a
  static page that is only as fresh as the moment it was published,
* the deployment configuration file, the full page URL every code
  carries, and the share card (text plus picture) shared in chat,
* the diagnostics: the net/error log, the verdict on why two clients on
  one machine were not connecting, and the run as it is shared.
-/
import RequestProject.Kant.Bytes
import RequestProject.Kant.Dasl
import RequestProject.Kant.Erdfa
import RequestProject.Kant.Paste
import RequestProject.Kant.Sneakernet
import RequestProject.Kant.Stego
import RequestProject.Kant.Sync
import RequestProject.Kant.Credits
import RequestProject.Kant.CodeMovie
import RequestProject.Kant.Sheaf
import RequestProject.Kant.Pipeline
import RequestProject.Kant.Diagnostics
import RequestProject.Kant.Text
import RequestProject.Kant.Clipboard
import RequestProject.Kant.Feed
import RequestProject.Kant.Meme
import RequestProject.Kant.Repost
import RequestProject.Kant.Strip
import RequestProject.Kant.Rendezvous
import RequestProject.Kant.Relay
import RequestProject.Kant.Uucp
import RequestProject.Kant.SiteCard

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.Demo

open Kant Kant.Bytes Kant.Dasl Kant.Sneakernet Kant.Stego Kant.Pipeline

/-- A sample paste. -/
def sample : Blob := "The Critique of Pure Paste".toUTF8.toList

def samplePaste : Paste :=
  { id := "paste_20260902_000000".toList
    title := "Kant <ZK> Pastebin".toList
    content := sample
    timestamp := "20260902_000000".toList }

/-! ## Content addressing -/

#guard samplePaste.witness.length = 64
#guard cidPrefix samplePaste.cid = daslPrefix
#guard cidType samplePaste.cid = 3
#guard (samplePaste.coords).l < 71 && (samplePaste.coords).m < 59 && (samplePaste.coords).n < 47
#guard (daslHex samplePaste.cid).length = 18
#guard monsterOrder = 808017424794512875886459904961710757005754368000000000

/-! ## eRDFa escaping -/

#guard Kant.Erdfa.escape "<div>".toList = "&lt;div&gt;".toList
#guard Kant.Erdfa.unescape (Kant.Erdfa.escape samplePaste.title) = samplePaste.title

/-! ## Framing and out-of-order reassembly -/

/-- Cut the paste into eight-byte frames (a tiny channel, to show the
framing at work). -/
def demoFrames : List Frame := frames 8 sample

#guard demoFrames.length = 4
#guard demoFrames.all (fun f => f.payload.length ≤ 8)
#guard reassemble demoFrames = sample
-- Frames delivered in reverse order still reassemble.
#guard reassemble demoFrames.reverse = sample

/-! ## Covert carriers -/

/-- A flat grey carrier image with room for two frames. -/
def carrier : Carrier := List.replicate 512 128

#guard (hide carrier (demoFrames.headD ⟨0, 0, []⟩)).length = carrier.length
#guard reveal (demoFrames.headD ⟨0, 0, []⟩).payload.length
         (hide carrier (demoFrames.headD ⟨0, 0, []⟩))
       = (demoFrames.headD ⟨0, 0, []⟩).payload
-- The carrier is disturbed by at most one unit per sample.
#guard ((hide carrier (demoFrames.headD ⟨0, 0, []⟩)).zip carrier).all
         (fun p => p.1 / 2 == p.2 / 2)

/-! ## Store and sync -/

def storeA : Store := Store.empty.put samplePaste
def storeB : Store := Kant.Sync.sync Store.empty [samplePaste, samplePaste]

#guard storeA.has samplePaste.witness
#guard storeB.has samplePaste.witness
#guard storeB.entries.length = 1

/-! ## Credits -/

open Kant.Credits in
def ledger : Ledger := (Ledger.empty.serve "peer-a".toList (4 * 1024)).serve "peer-b".toList 512

#guard ledger.balance "peer-a".toList = 4
#guard ledger.balance "peer-b".toList = 0
#guard ledger.totalEarned = 4
#guard (ledger.spend "peer-a".toList 5).isNone
#guard ((ledger.spend "peer-a".toList 3).map (fun L => L.balance "peer-a".toList)) = some 1

/-! ## The feed -/

/-- A reply to the sample paste, so the thread view has something to
show. -/
def replyPaste : Paste :=
  { id := "paste_20260902_000100".toList
    title := "Re: Kant <ZK> Pastebin".toList
    content := "Antinomies of pure pasting".toUTF8.toList
    timestamp := "20260902_000100".toList
    replyTo := some samplePaste.witness }

def feedStore : Store := (Store.empty.put samplePaste).put replyPaste

#guard (Kant.Feed.view feedStore).length = 2
#guard ((Kant.Feed.view feedStore).map Kant.Feed.Row.witness).contains samplePaste.witness
-- The newest post is shown first.
#guard ((Kant.Feed.newest (Kant.Feed.feed feedStore)).headD samplePaste).id = replyPaste.id
-- Search finds the phrase in the body, and only where it occurs.
#guard (Kant.Feed.search "pure".toList (Kant.Feed.feed feedStore)).length = 1
#guard (Kant.Feed.search "Critique".toList (Kant.Feed.feed feedStore)).length = 1
#guard (Kant.Feed.search "Hegel".toList (Kant.Feed.feed feedStore)).length = 0
-- The thread of the sample paste contains it and its one reply.
#guard (Kant.Feed.thread samplePaste (Kant.Feed.feed feedStore)).length = 2
-- Paging the feed two at a time shows every post exactly once.
#guard (Kant.Feed.paginate 1 (Kant.Feed.feed feedStore)).length = 2
#guard (Kant.Feed.paginate 1 (Kant.Feed.feed feedStore)).flatten = Kant.Feed.feed feedStore
-- The rendered row escapes the title but keeps it readable.
#guard Kant.Erdfa.unescape (Kant.Feed.row samplePaste).title = samplePaste.title

/-! ## Copy and paste -/

#guard Kant.Clipboard.pasteText (Kant.Clipboard.copyText samplePaste) = some samplePaste
#guard Kant.Clipboard.pasteText (Kant.Clipboard.copyText replyPaste) = some replyPaste
-- The clipboard text of a row is the clipboard text of its post.
#guard (Kant.Feed.row samplePaste).copy = Kant.Clipboard.copyText samplePaste
-- The numeric results copy and paste back unchanged.
#guard Kant.Clipboard.pasteReceipt
         (Kant.Clipboard.copyReceipt (Kant.Clipboard.receiptOf samplePaste 7))
       = some (Kant.Clipboard.receiptOf samplePaste 7)
/-- The clipboard text of the sample paste, with one byte prepended to
the content field but the original witness left in place. -/
def tamperedEnvelope : Kant.Clipboard.Envelope :=
  ⟨Kant.Clipboard.tagPaste,
    [Kant.Text.asciiBytes samplePaste.id, Kant.Text.asciiBytes samplePaste.title,
     0 :: samplePaste.content, Kant.Text.asciiBytes samplePaste.timestamp,
     Kant.Clipboard.optField none, Kant.Text.asciiBytes samplePaste.witness]⟩

-- Content that does not match the witness travelling with it is refused.
#guard (Kant.Clipboard.toPaste tamperedEnvelope).isNone
#guard (Kant.Clipboard.pasteText tamperedEnvelope.encode).isNone
-- Everything on screen copies and pastes back post for post.
#guard Kant.Clipboard.pasteAll (Kant.Clipboard.copyAll (Kant.Feed.feed feedStore))
       = some (Kant.Feed.feed feedStore)
-- A shared link carries the whole post.
#guard ((Kant.Clipboard.parseShareUrl
           (Kant.Clipboard.shareUrl "https://kant.zk/p".toList
             (Kant.Clipboard.ofPaste samplePaste))).bind Kant.Clipboard.toPaste)
       = some samplePaste

/-! ## Memes with embedded data -/

/-- A flat grey meme template, big enough to carry a whole post. -/
def memeTemplate : Kant.Meme.Template :=
  { topText := "WHEN THE CATEGORICAL IMPERATIVE".toList
    bottomText := "IS ALSO A CONTENT ADDRESS".toList
    carrier := List.replicate 8192 128 }

#guard 8 * (Kant.Meme.payload (Kant.Clipboard.ofPaste samplePaste)).length ≤ 8192
#guard (Kant.Meme.ofPaste memeTemplate samplePaste).length = 8192
#guard Kant.Meme.toPaste (Kant.Meme.ofPaste memeTemplate samplePaste) = some samplePaste
#guard Kant.Meme.toReceipt
         (Kant.Meme.ofReceipt memeTemplate (Kant.Clipboard.receiptOf samplePaste 7))
       = some (Kant.Clipboard.receiptOf samplePaste 7)
-- The picture is disturbed by at most one unit per sample.
#guard ((Kant.Meme.ofPaste memeTemplate samplePaste).zip memeTemplate.carrier).all
         (fun p => p.1 / 2 == p.2 / 2)
-- A page of the feed travels in one meme too, when the template has room.
#guard Kant.Meme.toPastes (Kant.Meme.ofPastes memeTemplate [samplePaste]) = some [samplePaste]
-- A meme carrying a tampered envelope is refused just as pasted text is.
#guard (Kant.Meme.toPaste (Kant.Meme.render memeTemplate tamperedEnvelope)).isNone
-- The address is visible on the meme, not only hidden in it.
#guard (Kant.Text.containsSub samplePaste.witness
         (Kant.Erdfa.unescape (Kant.Meme.caption memeTemplate samplePaste)))

/-! ## Quote reposts and share cards -/

/-- Quoting the sample post with a remark of one's own. -/
def sampleQuote : Kant.Repost.Quote :=
  Kant.Repost.quoteWith replyPaste samplePaste

-- A quote copies out and pastes back, commentary and original alike.
#guard Kant.Repost.pasteQuote (Kant.Repost.copyQuote sampleQuote) = some sampleQuote
#guard ((Kant.Repost.pasteQuote (Kant.Repost.copyQuote sampleQuote)).map
          Kant.Repost.Quote.original) = some samplePaste
-- A quote whose original has been doctored is refused outright.
#guard (Kant.Repost.pasteQuote
         (Kant.Clipboard.Envelope.encode
           ⟨Kant.Repost.tagQuote,
            [Kant.Text.asciiBytes (Kant.Clipboard.copyText replyPaste),
             Kant.Text.asciiBytes tamperedEnvelope.encode]⟩)).isNone
-- A quote also travels as one picture.  A quote carries two whole posts,
-- so the demo uses two short ones to stay inside the small template.
/-- A short post, for the picture-sized demo. -/
def briefPost : Paste :=
  { id := "a1".toList
    title := "hi".toList
    content := "yes".toUTF8.toList
    timestamp := "20260902".toList }

/-- A short remark quoting it. -/
def briefRemark : Paste :=
  { id := "a2".toList
    title := "re".toList
    content := "no".toUTF8.toList
    timestamp := "20260903".toList }

def briefQuote : Kant.Repost.Quote := Kant.Repost.quoteWith briefRemark briefPost

#guard 8 * (Kant.Meme.payload (Kant.Repost.ofQuote briefQuote)).length ≤ 8192
#guard Kant.Repost.memeToQuote (Kant.Repost.memeOfQuote memeTemplate briefQuote)
       = some briefQuote

/-- Where the cards point. -/
def cardBase : List Char := "https://kant.zk/p".toList

-- The card's visible headline and its embedded data travel together.
#guard ((Kant.Repost.readCard (Kant.Repost.postCard cardBase samplePaste)).bind
          Kant.Clipboard.toPaste) = some samplePaste
#guard ((Kant.Repost.readCard (Kant.Repost.receiptCard cardBase
           (Kant.Clipboard.receiptOf samplePaste 7))).bind Kant.Clipboard.toReceipt)
       = some (Kant.Clipboard.receiptOf samplePaste 7)
#guard ((Kant.Repost.readCard (Kant.Repost.bundleCard cardBase (Kant.Feed.feed feedStore))).bind
          Kant.Clipboard.toPastes) = some (Kant.Feed.feed feedStore)
-- The headline is readable, markup-free, and shows the address.
#guard Kant.Text.containsSub samplePaste.witness
         (Kant.Erdfa.unescape (Kant.Repost.headline samplePaste))
#guard !(Kant.Repost.headline samplePaste).contains '<'
#guard Kant.Text.containsSub (Kant.Repost.headline samplePaste)
         (Kant.Repost.postCard cardBase samplePaste)

/-! ## Strips: one share spread over several pictures -/

/-- Small stills, to show a share too big for one picture. -/
def stripTemplate : Kant.Meme.Template :=
  { memeTemplate with carrier := List.replicate 1024 128 }

-- A post goes out as eight stills of forty payload bytes each…
#guard (Kant.Strip.ofPaste stripTemplate 40 samplePaste).length = 8
#guard (Kant.Strip.ofPaste stripTemplate 40 samplePaste).all (fun c => c.length == 1024)
-- … and comes back whole.
#guard Kant.Strip.toPaste (Kant.Strip.ofPaste stripTemplate 40 samplePaste) = some samplePaste
-- The stills may be collected in any order.
#guard Kant.Strip.toPaste (Kant.Strip.ofPaste stripTemplate 40 samplePaste).reverse
       = some samplePaste
-- A quote — two whole posts — fits no single small picture, but fits a strip.
#guard Kant.Strip.toQuote (Kant.Strip.ofQuote stripTemplate 40 sampleQuote) = some sampleQuote
-- So does a whole page of the feed.
#guard Kant.Strip.toPastes (Kant.Strip.ofPastes stripTemplate 40 (Kant.Feed.feed feedStore))
       = some (Kant.Feed.feed feedStore)

/-! ## Code movies, Gödel numbers and circuits -/

open Kant.CodeMovie in
def movie : Movie := [[1, 1, 1, 2, 2], [3, 3, 3, 3], [4]]

open Kant.CodeMovie in
#guard rleEncode [1, 1, 1, 2, 2] = [(1, 3), (2, 2)]
open Kant.CodeMovie in
#guard rleDecode (rleEncode [1, 1, 1, 2, 2]) = [1, 1, 1, 2, 2]
open Kant.CodeMovie in
#guard unmovie (movieGodel movie) = movie
open Kant.CodeMovie in
#guard frameAt movie 4 = frameAt movie 1

open Kant.CodeMovie Kant.CodeMovie.Circuit in
def demoCircuit : Circuit := .and (.inp 0) (.not (.or (.inp 1) (.const false)))

open Kant.CodeMovie.Circuit in
#guard Kant.CodeMovie.Circuit.decode (encode demoCircuit) = some demoCircuit
open Kant.CodeMovie.Circuit in
#guard eval (fun i => i == 0) demoCircuit = true
open Kant.CodeMovie.Circuit in
#guard eval (fun _ => true) demoCircuit = false

/-! ## Finding other clients: invitations, rosters, relay and chat -/

open Kant.Rendezvous Kant.Relay in
/-- The secret behind the demo chat code. -/
def demoSecret : Blob := "kant-zk demo secret".toUTF8.toList

open Kant.Rendezvous in
/-- Two ways of reaching the demo peer. -/
def demoAddrs : List Address :=
  [⟨.libp2p, "/dns4/relay.example.org/tcp/443/wss".toList⟩, ⟨.iroh, "irohticket1".toList⟩]

open Kant.Rendezvous in
/-- The invitation a chat QR code carries. -/
def demoInvite : Invite :=
  ⟨"https://relay.example.org".toList, demoSecret, "alice".toList, demoAddrs⟩

open Kant.Rendezvous in
/-- Alice's peer announcement. -/
def demoAnnounce : Announce := ⟨"alice".toList, 7, demoAddrs⟩

open Kant.Rendezvous in
/-- Bob's peer announcement. -/
def demoAnnounceBob : Announce := ⟨"bob".toList, 2, [⟨.libp2p, "/dns4/b.example/tcp/443/wss".toList⟩]⟩

open Kant.Rendezvous Kant.Relay in
/-- A line of chat in the demo room. -/
def demoMsg : Msg := ⟨demoInvite.room, "alice".toList, 1, "hello".toUTF8.toList⟩

open Kant.Rendezvous Kant.Relay in
/-- A second line, from Bob. -/
def demoMsgBob : Msg := ⟨demoInvite.room, "bob".toList, 2, "hi there".toUTF8.toList⟩

open Kant.Rendezvous in
#guard (roomOf demoSecret).length = 64
open Kant.Rendezvous in
#guard String.ofList (roomOf demoSecret) =
  "bd71dd50a1ee00eaa91ea3fb701d151f8bc3059f81b1766c51ea8736f88acec1"
open Kant.Rendezvous in
#guard pasteInvite (copyInvite demoInvite) == some demoInvite
open Kant.Rendezvous in
#guard String.ofList (copyInvite demoInvite) =
  "6b7a696e76697465:68747470733a2f2f72656c61792e6578616d706c652e6f7267:6b616e742d7a6b2064656d6f20736563726574:616c696365:032f646e73342f72656c61792e6578616d706c652e6f72672f7463702f3434332f777373:0269726f687469636b657431"
open Kant.Rendezvous Kant.Sneakernet in
#guard (copyInvite demoInvite).length ≤ Channel.qr.capacity
open Kant.Rendezvous in
#guard parseInviteUrl (inviteUrl "https://kant.example/#".toList.dropLast demoInvite) == some demoInvite
open Kant.Rendezvous in
#guard parseAnnounce (printAnnounce demoAnnounce) == some demoAnnounce
open Kant.Rendezvous in
#guard String.ofList (printAnnounce demoAnnounce) =
  "6b7a70656572:616c696365:07:032f646e73342f72656c61792e6578616d706c652e6f72672f7463702f3434332f777373:0269726f687469636b657431"
open Kant.Relay in
#guard String.ofList demoMsg.witness =
  "2493daf48dda511be13a96a953fd10a49a744fc1cff4e209d1435304d28b6602"
open Kant.Relay in
#guard parseMsg (printMsg demoMsg) == some demoMsg
open Kant.Relay in
#guard String.ofList (printMsg demoMsg) =
  "6b7a63686174:62643731646435306131656530306561613931656133666237303164313531663862633330353966383162313736366335316561383733366638386163656331:616c696365:01:68656c6c6f:32343933646166343864646135313162653133613936613935336664313061343961373434666331636666346532303964313433353330346432386236363032"

open Kant.Bytes Kant.Text Kant.Clipboard Kant.Relay in
/-- The same line with the body swapped but the old witness left in place:
what a dishonest relay would hand out. -/
def demoTamperedLine : List Char :=
  (Envelope.mk tagChat
    [asciiBytes demoMsg.room, asciiBytes demoMsg.sender, natToBytesBE demoMsg.seq,
      "goodbye".toUTF8.toList, asciiBytes demoMsg.witness]).encode

open Kant.Relay in
#guard parseMsg demoTamperedLine == none
open Kant.Relay in
#guard accept [] demoTamperedLine == []

open Kant.Rendezvous Kant.Relay in
/-- The relay after Alice and Bob have both announced themselves. -/
def demoServer : Server :=
  ((Server.empty.post demoInvite.room (printAnnounce demoAnnounce)).post
    demoInvite.room (printAnnounce demoAnnounceBob))

open Kant.Rendezvous Kant.Relay in
#guard (demoServer.fetch demoInvite.room 0).2 = 2
open Kant.Rendezvous Kant.Relay in
#guard (demoServer.fetch demoInvite.room 1).1.length = 1
open Kant.Rendezvous Kant.Relay in
#guard Roster.knows (acceptPeers [] (demoServer.fetch demoInvite.room 0).1) "bob".toList
open Kant.Rendezvous Kant.Relay in
#guard Roster.knows (acceptPeers [] (demoServer.fetch demoInvite.room 0).1) "alice".toList
open Kant.Rendezvous Kant.Relay in
#guard (Roster.best (acceptPeers [] (demoServer.fetch demoInvite.room 0).1) "alice".toList)
    == some demoAnnounce

open Kant.Relay in
/-- Two chat lines, as they leave the relay. -/
def demoChatLines : List (List Char) := [printMsg demoMsg, printMsg demoMsgBob]

open Kant.Relay in
#guard (receive [] demoChatLines).length = 2
open Kant.Relay in
#guard transcript (receive [] demoChatLines) == transcript (receive [] demoChatLines.reverse)
open Kant.Relay in
#guard (transcript (receive [] demoChatLines)).map (fun m => m.seq) = [1, 2]
open Kant.Relay in
#guard transcript (receive [] (demoChatLines ++ [demoTamperedLine]))
    == transcript (receive [] demoChatLines)

/-! ## The static sneakernet: no relay at all

Alice writes two lines while offline, copies her mailbag into a direct
message, and Bob pastes it.  Nothing else happens: there is no server in
any of what follows. -/

open Kant.Rendezvous Kant.Relay Kant.Uucp in
/-- Alice, after writing two lines with nobody connected. -/
def demoAlice : Node :=
  ((Node.blank "alice".toList).write demoInvite.room "hello".toUTF8.toList).write
    demoInvite.room "second".toUTF8.toList

open Kant.Uucp in
/-- Bob, after pasting Alice's mailbag out of a DM. -/
def demoBob : Node := (Node.blank "bob".toList).paste demoAlice.bag

open Kant.Rendezvous Kant.Uucp in
/-- Carol, who has a line of her own and has met nobody. -/
def demoCarol : Node := (Node.blank "carol".toList).write demoInvite.room "ping".toUTF8.toList

open Kant.Uucp in
#guard demoAlice.spool.length = 2
open Kant.Uucp in
#guard demoBob.spool.length = 2
open Kant.Uucp in
#guard demoBob.view == demoAlice.view
open Kant.Uucp in
#guard demoAlice.bag.length = 1192
open Kant.Bytes Kant.Text Kant.Uucp in
#guard String.ofList (Kant.Bytes.witness (asciiBytes demoAlice.bag)) =
  "1e3c0d3ce7a0b792ed7bcb7d2cf3ea1dc1f6c3bdb7b1ff28ff5bbc0c036b3073"
open Kant.Uucp in
#guard openBag demoAlice.bag == some demoAlice.view
open Kant.Uucp in
#guard readBagUrl (bagUrl "https://kant.example/".toList demoAlice.spool) == some demoAlice.spool

-- Bob, who now knows exactly what Alice knows, hands out the same code.
open Kant.Uucp in
#guard demoBob.bag == demoAlice.bag

-- Pasting the same code twice tells Bob nothing new.
open Kant.Uucp in
#guard (demoBob.paste demoAlice.bag).spool.length = 2

open Kant.Bytes Kant.Text Kant.Clipboard Kant.Relay Kant.Uucp in
/-- A mailbag with one doctored line in it. -/
def demoTamperedBag : List Char :=
  (Envelope.mk tagBag [asciiBytes demoTamperedLine, asciiBytes (printMsg demoMsg)]).encode

open Kant.Uucp in
#guard openBag demoTamperedBag == none
open Kant.Uucp in
#guard (demoBob.paste demoTamperedBag).spool.length = 2

open Kant.Uucp in
/-- A mailbag too big for one tweet, as a numbered thread. -/
def demoThread : List (List Char) := thread 100 demoAlice.bag

open Kant.Uucp in
#guard demoThread.length = 12
open Kant.Uucp in
#guard demoThread.all (fun t => t.length ≤ Carrier.tweet.capacity)
open Kant.Uucp in
#guard readThread demoThread.reverse == some demoAlice.bag

-- Alice and Carol swap bags and agree, with no relay between them.
open Kant.Uucp in
#guard (exchange demoAlice demoCarol).1.view == (exchange demoAlice demoCarol).2.view

-- A bang path: Alice's bag is carried to Carol, Carol's to Dave.
open Kant.Uucp in
#guard (route demoAlice [demoCarol, Node.blank "dave".toList]).spool.length = 3

open Kant.Uucp in
/-- The static page Alice publishes, and the visitor who pastes it. -/
def demoSite : Site := Site.empty.publish "/feed.txt".toList demoAlice

open Kant.Uucp in
#guard (demoSite.visit "/feed.txt".toList (Node.blank "vic".toList)).spool.length = 2
open Kant.Uucp in
#guard (demoSite.serve "/feed.txt".toList).1.files.length = 1
-- A line Alice writes *after* publishing is not in the published page:
-- the visitor stays stale until a fresher code is pasted.
open Kant.Rendezvous Kant.Uucp in
#guard (demoSite.visit "/feed.txt".toList (Node.blank "vic".toList)).spool.length
    < (demoAlice.write demoInvite.room "third".toUTF8.toList).spool.length
open Kant.Rendezvous Kant.Uucp in
#guard ((Site.empty.publish "/feed.txt".toList
      (demoAlice.write demoInvite.room "third".toUTF8.toList)).visit
    "/feed.txt".toList (Node.blank "vic".toList)).spool.length = 3

/-! ## The site configuration, the page URL, and the share card

The configuration file names the deployment; every code and link then
carries the whole URL of the page, `origin ++ "#" ++ address`. -/

open Kant.SiteCard in
/-- The deployment this checkout is configured for (`kant.config`). -/
def demoConfig : Kant.SiteCard.Config :=
  ⟨"https://kant.cicada71.net/".toList, "kant-zk-pastebin".toList, "./kant-logo.svg".toList,
   "the Kant pastebin logo".toList⟩

open Kant.SiteCard in
-- The configuration file is written and read back unchanged.
#guard String.ofList (renderConfig demoConfig) =
  "origin = https://kant.cicada71.net/\ncaption = kant-zk-pastebin\n\
   picture = ./kant-logo.svg\nalt = the Kant pastebin logo\n"
open Kant.SiteCard in
#guard parseConfig (renderConfig demoConfig) == some demoConfig
open Kant.SiteCard in
-- A comment line is ignored.
#guard parseConfig ("# where this deployment lives".toList ++ '\n' :: renderConfig demoConfig)
    == some demoConfig

open Kant.SiteCard in
-- The page URL of the sample post: the configured origin, a `'#'`, and
-- the 64-hex address of the content.
#guard String.ofList (pasteUrl demoConfig samplePaste) =
  "https://kant.cicada71.net/#ff810f291f187b808a0183f83c0466874573ef5c4c6d7d9ed430c6f7d710f605"
open Kant.SiteCard in
#guard (pasteUrl demoConfig samplePaste).length = 91
open Kant.SiteCard in
#guard String.ofList (urlAddress (pasteUrl demoConfig samplePaste)) = String.ofList samplePaste.witness
open Kant.SiteCard in
-- The code carries the whole URL, and the client still reads the payload
-- out of the fragment.
#guard parseQrPayload (qrPayload demoConfig (Kant.Clipboard.ofPaste samplePaste))
    == some (Kant.Clipboard.ofPaste samplePaste)

open Kant.SiteCard in
/-- The share card for the sample post: its URL, the configured caption
and the configured picture. -/
def demoCard : Kant.SiteCard.Card := cardOf demoConfig samplePaste

open Kant.SiteCard in
#guard (cardLine demoCard).length = 304
open Kant.SiteCard in
#guard String.ofList (Kant.Bytes.witness (Kant.Text.asciiBytes (cardLine demoCard))) =
  "fe2f60c16f4c13313602b158fd9e158a01f33032d2041c97fa1d8f5f8e9bc970"
open Kant.SiteCard in
#guard readCardLine (cardLine demoCard) == some demoCard

open Kant.SiteCard in
/-- A tiny five-by-five stand-in for the code's modules. -/
def demoModules : List (List Bool) :=
  [[true, false, true, false, true], [false, true, false, true, false],
   [true, true, false, false, true], [false, false, true, true, false],
   [true, false, true, false, true]]

open Kant.SiteCard in
-- The exported picture still carries the card, caption, logo and all.
#guard readCard (cardSvg demoCard demoModules 8 4) == some demoCard
open Kant.SiteCard in
#guard Kant.Text.containsSub (Kant.Erdfa.escape demoCard.caption) (cardSvg demoCard demoModules 8 4)
open Kant.SiteCard in
#guard Kant.Text.containsSub (Kant.Erdfa.escape demoCard.picture) (cardSvg demoCard demoModules 8 4)
open Kant.SiteCard in
#guard Kant.Text.containsSub (Kant.Erdfa.escape demoCard.url) (cardSvg demoCard demoModules 8 4)
open Kant.SiteCard in
-- A caption full of markup cannot break the document.
#guard readCard (cardSvg ⟨demoCard.url, "</svg><script>alert(1)</script>".toList,
    demoCard.picture, demoCard.alt⟩ demoModules 8 4)
  == some ⟨demoCard.url, "</svg><script>alert(1)</script>".toList, demoCard.picture, demoCard.alt⟩
open Kant.SiteCard in
#guard ¬ Kant.Text.containsSub "<script>".toList
  (Kant.Erdfa.escape "</svg><script>alert(1)</script>".toList)

open Kant.SiteCard in
-- Shared in a chat room, the card arrives as the same card.
#guard readChatCard (Kant.Relay.printMsg (chatMsg "room7".toList "alice".toList 3 demoCard))
    == some demoCard
open Kant.SiteCard in
-- Pasted as plain text into any chat window, it still comes back whole.
#guard readChatText (chatText demoCard) == some demoCard
open Kant.SiteCard in
#guard (Kant.SiteCard.splitCh '\n' (chatText demoCard)).length = 3

/-! ## The diagnostics: the run, the verdict, and what is shared

These are the vectors `web/diag-test.mjs` pins the browser client to. -/

open Kant.Diagnostics in
/-- Two lines of a real run. -/
def demoProbe : Event :=
  ⟨0, 12, .info, .probe, "probing relay".toList, "http://localhost:8787/health".toList⟩

open Kant.Diagnostics in
def demoFailure : Event :=
  ⟨1, 340, .error, .relay, "relay post failed".toList, "status=404".toList⟩

open Kant.Diagnostics in
#guard String.ofList (printEvent demoProbe) ==
  "6b7a6c6f67::0c:01:02:70726f62696e672072656c6179:687474703a2f2f6c6f63616c686f73743a383738372f6865616c7468"
open Kant.Diagnostics in
#guard String.ofList (printEvent demoFailure) ==
  "6b7a6c6f67:01:0154:03:03:72656c617920706f7374206661696c6564:7374617475733d343034"
open Kant.Diagnostics in
-- A written line reads back as the same event.
#guard parseEvent (printEvent demoFailure) == some demoFailure

open Kant.Diagnostics in
/-- A short log: four lines kept out of six recorded. -/
def demoLog : Log :=
  (((((Log.empty 4).record 1 .info .app "page opened".toList "".toList).record 12 .info .probe
      "probing relay".toList "http://localhost:8787/health".toList).record 40 .warn .config
      "no relay configured".toList "".toList).record 90 .error .relay
      "the line did not reach the relay".toList "status=404".toList).record 95 .info .bus
      "a line arrived from another tab".toList "room=deadbeef".toList

open Kant.Diagnostics in
#guard demoLog.events.length == 4
open Kant.Diagnostics in
#guard demoLog.dropped == 1
open Kant.Diagnostics in
#guard demoLog.total == 5
open Kant.Diagnostics in
-- The newest line is never the one dropped.
#guard (demoLog.events.getLast?.map (·.seq)) == some 4
open Kant.Diagnostics in
-- …and the numbers still increase, with none reused.
#guard (demoLog.events.map (·.seq)) == [1, 2, 3, 4]
open Kant.Diagnostics in
-- The whole run reads back exactly.
#guard parseLog (renderLog demoLog) == some demoLog.events
open Kant.Diagnostics in
-- A line quoting the room is withheld from a shared run; nothing else is.
#guard ((demoLog.share ["deadbeef".toList]).events.length) == 3
open Kant.Diagnostics in
#guard (demoLog.share ["deadbeef".toList]).events.all
  (fun e => ¬ Kant.Text.containsSub "deadbeef".toList e.detail)

open Kant.Connectivity in
/-- Two browsers on one machine, page served by a plain static host: the
failure the user hit. -/
def staticHost : Reachability := ⟨[], false, "https://static.example".toList, false⟩

open Kant.Connectivity in
/-- The same machine, page served by `node server/relay.mjs --static web`. -/
def selfHosted : Reachability := ⟨[], false, "http://localhost:8787".toList, true⟩

open Kant.Connectivity in
#guard effectiveRelay staticHost == []
open Kant.Connectivity in
#guard String.ofList (effectiveRelay selfHosted) == "http://localhost:8787"
open Kant.Connectivity in
#guard decide (diagnose ⟨"room".toList, staticHost, true, 1⟩ ⟨"room".toList, staticHost, true, 2⟩
  = Verdict.onlyThisBrowser)
open Kant.Connectivity in
#guard decide (diagnose ⟨"room".toList, selfHosted, true, 1⟩ ⟨"room".toList, selfHosted, true, 2⟩
  = Verdict.ok)
open Kant.Connectivity in
#guard decide (diagnose ⟨"room".toList, selfHosted, true, 1⟩ ⟨"other".toList, selfHosted, true, 2⟩
  = Verdict.roomMismatch)
open Kant.Connectivity in
#guard String.ofList (explain (diagnose ⟨"room".toList, staticHost, true, 1⟩
    ⟨"room".toList, staticHost, true, 2⟩)) ==
  "only-this-browser: two separate browsers with no relay between them; serve the page with `node server/relay.mjs --static web`, or set `relay =`"

open Kant.Diagnostics in
/-- The report the diagnostics page shares. -/
def demoReport : Report :=
  ⟨.onlyThisBrowser, ref "room".toList, "http://localhost:8787".toList,
    [demoProbe, demoFailure]⟩

open Kant.Diagnostics in
#guard String.ofList (renderReport demoReport) ==
  "6b7a64696167:05:3665373163653336:687474703a2f2f6c6f63616c686f73743a38373837\n6b7a6c6f67::0c:01:02:70726f62696e672072656c6179:687474703a2f2f6c6f63616c686f73743a383738372f6865616c7468\n6b7a6c6f67:01:0154:03:03:72656c617920706f7374206661696c6564:7374617475733d343034"
open Kant.Diagnostics in
#guard parseReport (renderReport demoReport) == some demoReport
open Kant.Diagnostics in
#guard String.ofList (ref "kzinvite-secret".toList) == "5f40d0e7"

end Kant.Demo
