/-
# The worked example, checked at elaboration time

A small domain — an input datum, a theorem about it, the proof that
establishes the theorem, the claim, and a second value that is only
asserted — run through the whole skill: emission in five formats,
re-import, the relational tables, the ledger, the coverage summary, the
package, and the policy that keeps an assertion from becoming a proof.

Every `#guard` below is checked when this file is compiled.  The values
marked *golden* are the ones the JavaScript implementation is pinned to.
-/
import Mathlib
import RequestProject.Kant.Domain.Package

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.Dom.Tests

open Kant.Codec
open Kant.Dom

/-! ## The example domain -/

/-- Provenance shared by the example objects. -/
def exProv : Prov :=
  { sourceSystem := "example".toList, sourceFile := "Theory/X.lean".toList,
    sourceFormat := .text, importedAt := 0, transformedAt := 0, transformations := [],
    parent := [] }

/-- The input datum: 12. -/
def exInput : DomObj :=
  { id := "input_001".toList, kind := "datum".toList, name := "twelve".toList,
    value := .int 12, claim := "the number twelve".toList, inputs := [], parameters := [],
    transformations := [], outputs := ["theorem_001".toList], claimRefs := [],
    evidenceRefs := [], proofRefs := [], errorRefs := [], truth := .asserted,
    provenance := some exProv }

/-- The theorem: 12 squared is 144, established by a proof. -/
def exTheorem : DomObj :=
  { id := "theorem_001".toList, kind := "theorem".toList, name := "twelve_sq".toList,
    value := .int 144, claim := "12 * 12 = 144".toList, inputs := ["input_001".toList],
    parameters := [], transformations := [], outputs := [], claimRefs := ["claim_001".toList],
    evidenceRefs := [], proofRefs := ["proof_001".toList], errorRefs := [], truth := .proven,
    provenance := some exProv }

/-- A value nobody proved. -/
def exAsserted : DomObj :=
  { id := "datum_002".toList, kind := "datum".toList, name := "guess".toList,
    value := .int 144, claim := "144, on somebody's word".toList, inputs := [],
    parameters := [], transformations := [], outputs := [], claimRefs := [],
    evidenceRefs := [], proofRefs := [], errorRefs := [], truth := .asserted,
    provenance := some exProv }

/-- The proof of the theorem. -/
def exProof : ProofRec :=
  { id := "proof_001".toList, name := "twelve_sq".toList, kind := "lean4".toList,
    sourceFile := "Theory/X.lean".toList, sourceLoc := "17".toList,
    inputRefs := ["input_001".toList], assumptions := [],
    procedure := "evaluation".toList, outputRefs := ["theorem_001".toList],
    claimRefs := ["claim_001".toList], dependsOn := [], status := .valid,
    certificate := some { kind := "lean4-kernel".toList, digest := "144".toList,
                          location := "Theory/X.lean:17".toList, evidence := .machineChecked },
    source := "example".toList, provenance := some exProv }

/-- The claim the proof establishes. -/
def exClaim : Claim :=
  { id := "claim_001".toList, objectRef := "theorem_001".toList, text := "12 * 12 = 144".toList,
    truth := .proven, proofRefs := ["proof_001".toList] }

/-- The example domain, with the relations filled in from the catalog. -/
def exDomain : Domain :=
  withDerivedRelations
    { id := "example-domain".toList, name := "example".toList, version := "1.0".toList,
      description := "one proven value, one asserted value".toList,
      objects := [exInput, exTheorem, exAsserted], relations := [], proofs := [exProof],
      claims := [exClaim], evidence := [], schemas := [], errors := [], provenance := [exProv] }

/-! ## Every representation round-trips -/

/-- Whether one format returns the canonical graph. -/
def roundTrips (f : Fmt) : Bool := (parse f (emit f exDomain)).map Domain.text == some exDomain.text

#guard roundTrips .ipdl
#guard roundTrips .xml
#guard roundTrips .csv
#guard roundTrips .yaml
#guard roundTrips .text
#guard roundTrips .canonical

/- And every one of them carries the same canonical hash. -/
#guard allFormats.all (fun f => (parse f (emit f exDomain)).map Domain.hash == some exDomain.hash)

/- The relational tables rebuild the graph. -/
#guard (objectsOfTable (objectsTable exDomain)).map (fun os => os.map DomObj.id)
    == some [exInput.id, exTheorem.id, exAsserted.id]
#guard (proofsOfTable (proofsTable exDomain)).map (fun ps => ps.map ProofRec.id)
    == some [exProof.id]
#guard (relationsOfTable (relationsTable exDomain)) == some exDomain.relations
#guard (domainOfTables (metaTable exDomain) (objectsTable exDomain) (proofsTable exDomain)
    (relationsTable exDomain)).map Domain.text == some exDomain.text

/- The readable text form carries the readable rendering *and* the graph. -/
#guard (parseTextFull (emitText exDomain)).map (fun p => p.2.text) == some exDomain.text
#guard (parseTextFull (emitText exDomain)).map (fun p => p.1) == some (Domain.report exDomain)

/-! ## Coverage and the ledger -/

#guard coverage exDomain exTheorem == Coverage.proven
#guard coverage exDomain exInput == Coverage.unproven
#guard coverage exDomain exAsserted == Coverage.unproven

#guard summary exDomain == { objects := 3, proven := 1, partiallyProven := 0, unproven := 2,
                             contradicted := 0, proofs := 1, validProofs := 1 }

#guard (ledger exDomain).map (fun r => r.objectId)
    == [exInput.id, exTheorem.id, exAsserted.id]
#guard (ledger exDomain).map (fun r => r.proofId)
    == ["--".toList, "proof_001".toList, "--".toList]
#guard (ledger exDomain).map (fun r => r.coverage.name)
    == [Coverage.unproven.name, Coverage.proven.name, Coverage.unproven.name]

/- The proven row cites a proof, and the unproven rows do not. -/
#guard (ledgerRow exDomain exTheorem).proofStatus == some PStatus.valid
#guard (ledgerRow exDomain exAsserted).proofStatus == none

/-! ## Both directions of the walk -/

/- Data → proof. -/
#guard (findProof exDomain "proof_001".toList).map ProofRec.status == some PStatus.valid

/- Proof → inputs. -/
#guard (findProof exDomain "proof_001".toList).map (fun p => p.inputRefs)
    == some ["input_001".toList]

/- Proof → outputs → data. -/
#guard ((findProof exDomain "proof_001".toList).bind
    (fun p => (p.outputRefs.head?).bind (findObj exDomain))).map (fun o => o.proofRefs)
    == some ["proof_001".toList]

/- The edges are in the relations table both ways. -/
#guard exDomain.relations.contains ⟨"proof_001".toList, .proves, "theorem_001".toList⟩
#guard exDomain.relations.contains ⟨"theorem_001".toList, .provenBy, "proof_001".toList⟩
#guard exDomain.relations.contains ⟨"input_001".toList, .inputTo, "proof_001".toList⟩

/-! ## No silent claims -/

/- An assertion does not become a proof by being asserted louder. -/
#guard (step exDomain exAsserted.id (.assertedBy "someone".toList) .asserted).1 == Truth.asserted
#guard (step exDomain exAsserted.id (.importedFrom "elsewhere".toList) .imported).1
    == Truth.imported

/- Citing a proof that is not in the catalog changes nothing and records
an error. -/
#guard (step exDomain exAsserted.id (.validated "proof_404".toList) .asserted).1 == Truth.asserted
#guard (step exDomain exAsserted.id (.validated "proof_404".toList) .asserted).2.isSome

/- Citing one that is, and reports `VALID`, does. -/
#guard (step exDomain exAsserted.id (.validated "proof_001".toList) .asserted).1 == Truth.proven

/- Leaving `PROVEN` is always reported, and reported as fatal. -/
#guard ((step exDomain exTheorem.id (.invalidation "proof_001".toList) .proven).2.map
    Err.severity) == some Severity.fatal

/-! ## Error reconciliation -/

#guard (reconcileInt "obj".toList "n".toList "144".toList).repair == Repair.stringToInteger
#guard ((reconcileInt "obj".toList "n".toList "144".toList).result.map canonEnc)
    == some (canonEnc (Val.int 144))
#guard (reconcileInt "obj".toList "n".toList "one".toList).repair == Repair.unresolved
#guard (reconcileInt "obj".toList "n".toList "one".toList).error.recoverable == false

/-! ## The package -/

#guard (package exDomain).map Prod.fst == packageFiles
#guard (packageRead (package exDomain)).map Domain.text == some exDomain.text
#guard (exchange exDomain).2

/-! ## A scanned corpus -/

/-- Three declarations as a scanner might have found them: one proved,
one still carrying a `sorry`, one definition. -/
def exDecls : List Decl :=
  [{ name := "Kant.Dom.parse_emit".toList, kind := "theorem".toList,
     file := "RequestProject/Kant/Domain/Emit.lean".toList, line := 150,
     statement := "parse f (emit f d) = some d".toList, sorried := false, axiomsOk := true,
     deps := ["Kant.Dom.emit".toList] },
   { name := "Kant.Dom.emit".toList, kind := "def".toList,
     file := "RequestProject/Kant/Domain/Emit.lean".toList, line := 140,
     statement := "Fmt → Domain → List Char".toList, sorried := false, axiomsOk := true,
     deps := [] },
   { name := "Example.unfinished".toList, kind := "theorem".toList,
     file := "RequestProject/Example.lean".toList, line := 3,
     statement := "still open".toList, sorried := true, axiomsOk := true, deps := [] }]

/-- The catalog of that corpus. -/
def exCatalog : Domain := catalog "kant-corpus".toList "the example corpus".toList exDecls

#guard exCatalog.objects.length == 3
#guard exCatalog.proofs.length == 2
#guard exCatalog.claims.length == 2

/- The proved theorem is `PROVEN`, with a `VALID`, machine-checked proof. -/
#guard (findObj exCatalog (objId "Kant.Dom.parse_emit".toList)).map DomObj.truth
    == some Truth.proven
#guard (findProof exCatalog (proofIdOf "Kant.Dom.parse_emit".toList)).map ProofRec.status
    == some PStatus.valid
#guard ((findProof exCatalog (proofIdOf "Kant.Dom.parse_emit".toList)).bind
    ProofRec.certificate).map Cert.evidence == some Evid.machineChecked

/- The one with a `sorry` is not proven, is `PARTIAL`, and has no
certificate to point at. -/
#guard (findObj exCatalog (objId "Example.unfinished".toList)).map DomObj.truth
    == some Truth.unresolved
#guard (findProof exCatalog (proofIdOf "Example.unfinished".toList)).map ProofRec.status
    == some PStatus.«partial»
#guard ((findProof exCatalog (proofIdOf "Example.unfinished".toList)).map
    (fun p => p.certificate.isNone)) == some true

/- The definition is an object of the domain, asserted rather than
proven, and it is what the theorem consumes. -/
#guard (findObj exCatalog (objId "Kant.Dom.emit".toList)).map DomObj.truth == some Truth.asserted
#guard (findProof exCatalog (proofIdOf "Kant.Dom.parse_emit".toList)).map (fun p => p.inputRefs)
    == some [objId "Kant.Dom.emit".toList]

/- The coverage of the corpus: one proven, one partially proven, one
definition that nobody claims is proven. -/
#guard summary exCatalog == { objects := 3, proven := 1, partiallyProven := 1, unproven := 1,
                              contradicted := 0, proofs := 2, validProofs := 1 }

/- And the catalog round-trips like any other domain. -/
#guard allFormats.all (fun f => (parse f (emit f exCatalog)).map Domain.text
    == some exCatalog.text)

/-! ## Golden vectors shared with the JavaScript -/

/-- The canonical hash of the example domain. -/
def goldenHash : List Char := exDomain.hash

/-- The canonical hash of the theorem object. -/
def goldenObjectHash : List Char := exTheorem.hash

#guard goldenHash.length == 64
#guard goldenObjectHash.length == 64

end Kant.Dom.Tests
