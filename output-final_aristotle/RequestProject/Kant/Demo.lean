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
* Gödel numbering of a code movie and of a circuit.
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

end Kant.Demo
