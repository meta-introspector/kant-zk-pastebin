/-
# Relational CSV projections

§11 of the standard asks that CSV be a set of *relational* tables —
`objects.csv`, `proofs.csv`, `relations.csv`, `proof-ledger.csv` — rather
than one flattened sheet, and that the set be reconstructable.

This module is the table machinery: variable-width CSV rows that quote
properly (`readCells_cellsText`), whole tables with a header line
(`readTable_tableText`), and the projections themselves.  Cells that hold
structure — a list of identifiers, a value, a provenance record — carry
the canonical serialization of that structure, so nothing has to be
flattened and nothing is lost: `objectsTable_recovers`,
`proofsTable_recovers`, `relationsTable_recovers` and
`csvPackage_recovers` read the tables back into the very domain they came
from.
-/
import Mathlib
import RequestProject.Kant.Domain.Ledger

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.Dom

open Kant.Codec

/-! ## Variable-width CSV rows -/

/-- One row of cells as a line of CSV. -/
def cellsText : List (List Char) → List Char
  | [] => ['\n']
  | [c] => csvField c ++ ['\n']
  | c :: cs => csvField c ++ ',' :: cellsText cs

/-- Reading one quoted cell and the delimiter that follows it. -/
def readCellSep : List Char → Option (List Char × Char × List Char)
  | '"' :: s =>
      match readCsvField s with
      | some (v, c :: r) => some (v, c, r)
      | _ => none
  | _ => none

theorem readCellSep_csvField (sep : Char) (hsep : sep ≠ '"') (s rest : List Char) :
    readCellSep (csvField s ++ sep :: rest) = some (s, sep, rest) := by
  have h := readCsvField_csvField s (sep :: rest) (by simp [NotQuote, hsep])
  simp only [csvField, List.cons_append, List.append_assoc]
  rw [readCellSep]
  simp [h]

/-- Reading one row of cells. -/
def readCells : Nat → List Char → Option (List (List Char) × List Char)
  | 0, _ => none
  | fuel + 1, s =>
      match s with
      | '\n' :: r => some ([], r)
      | _ =>
        match readCellSep s with
        | some (v, sep, r) =>
            if sep = '\n' then some ([v], r)
            else if sep = ',' then (readCells fuel r).map (fun p => (v :: p.1, p.2))
            else none
        | none => none

theorem csvField_length (s : List Char) : 2 ≤ (csvField s).length := by
  simp [csvField]

/-- A row is at least as long as the number of cells in it. -/
theorem length_cellsText (cs : List (List Char)) : cs.length < (cellsText cs).length := by
  induction cs with
  | nil => simp [cellsText]
  | cons c cs ih =>
      cases cs with
      | nil =>
          have := csvField_length c
          simp only [cellsText, List.length_append, List.length_cons, List.length_nil]
          omega
      | cons c2 cs2 =>
          have := csvField_length c
          simp only [cellsText, List.length_append, List.length_cons] at ih ⊢
          omega

/-- Reading a row that starts with a quoted cell. -/
theorem readCells_head (fuel : Nat) (c : List Char) (sep : Char) (rest : List Char)
    (hsep : sep ≠ '"') :
    readCells (fuel + 1) (csvField c ++ sep :: rest) =
      (if sep = '\n' then some ([c], rest)
       else if sep = ',' then (readCells fuel rest).map (fun p => (c :: p.1, p.2))
       else none) := by
  have hcell := readCellSep_csvField sep hsep c rest
  simp only [csvField, List.cons_append, List.append_assoc] at hcell ⊢
  rw [readCells]
  · simp only [hcell]
  · intro r hr
    simp at hr

/-- **A row of cells round-trips**, whatever the cells contain. -/
theorem readCells_cellsText (cs : List (List Char)) :
    ∀ fuel rest, cs.length < fuel → readCells fuel (cellsText cs ++ rest) = some (cs, rest) := by
  induction cs with
  | nil =>
      intro fuel rest hf
      cases fuel with
      | zero => simp at hf
      | succ f => simp [cellsText, readCells]
  | cons c cs ih =>
      intro fuel rest hf
      cases fuel with
      | zero => simp at hf
      | succ f =>
          cases cs with
          | nil =>
              have hcat : cellsText [c] ++ rest = csvField c ++ '\n' :: rest := by
                simp [cellsText]
              rw [hcat, readCells_head f c '\n' rest (by decide)]
              simp
          | cons c2 cs2 =>
              have hcat : cellsText (c :: c2 :: cs2) ++ rest
                  = csvField c ++ ',' :: (cellsText (c2 :: cs2) ++ rest) := by
                simp [cellsText]
              have htail := ih f rest (by simp at hf ⊢; omega)
              rw [hcat, readCells_head f c ',' (cellsText (c2 :: cs2) ++ rest) (by decide)]
              simp [htail]

/-! ## Tables -/

/-- A whole table: a header line and one line per row. -/
def tableText (header : List (List Char)) (rows : List (List (List Char))) : List Char :=
  cellsText header ++ rows.flatMap cellsText

/-- Reading the rows of a table. -/
def readAllRows : Nat → List Char → Option (List (List (List Char)))
  | 0, _ => none
  | _ + 1, [] => some []
  | fuel + 1, s =>
      match readCells (s.length + 1) s with
      | some (cs, r) => (readAllRows fuel r).map (fun rs => cs :: rs)
      | none => none

theorem cellsText_ne_nil (cs : List (List Char)) : cellsText cs ≠ [] := by
  intro h
  have := length_cellsText cs
  rw [h] at this
  simp at this

theorem length_flatMap_cellsText (rows : List (List (List Char))) :
    rows.length ≤ (rows.flatMap cellsText).length := by
  induction rows with
  | nil => simp
  | cons r rs ih =>
      have h1 : 1 ≤ (cellsText r).length := by
        have := length_cellsText r
        omega
      simp only [List.flatMap_cons, List.length_append, List.length_cons]
      omega

theorem readAllRows_flatMap (rows : List (List (List Char))) :
    ∀ fuel, rows.length < fuel → readAllRows fuel (rows.flatMap cellsText) = some rows := by
  induction rows with
  | nil =>
      intro fuel hf
      cases fuel with
      | zero => simp at hf
      | succ f => simp [readAllRows]
  | cons r rs ih =>
      intro fuel hf
      cases fuel with
      | zero => simp at hf
      | succ f =>
          have htail := ih f (by simp at hf ⊢; omega)
          obtain ⟨c, t, hct⟩ : ∃ c t, cellsText r = c :: t := by
            cases h : cellsText r with
            | nil => exact absurd h (cellsText_ne_nil r)
            | cons c t => exact ⟨c, t, rfl⟩
          have hcat : (r :: rs).flatMap cellsText = c :: (t ++ rs.flatMap cellsText) := by
            simp [List.flatMap_cons, hct]
          have hrow : readCells ((c :: (t ++ rs.flatMap cellsText)).length + 1)
              (cellsText r ++ rs.flatMap cellsText) = some (r, rs.flatMap cellsText) := by
            refine readCells_cellsText r _ _ ?_
            have hlt := length_cellsText r
            rw [hct] at hlt
            simp only [List.length_cons, List.length_append] at hlt ⊢
            omega
          rw [hcat, readAllRows]
          · rw [hct] at hrow
            simp only [List.cons_append] at hrow
            rw [hrow]
            simp [htail]
          · simp

/-- Reading a whole table: the header line, then the rows. -/
def readTable (s : List Char) : Option (List (List Char) × List (List (List Char))) :=
  match readCells (s.length + 1) s with
  | some (header, rest) => (readAllRows (rest.length + 1) rest).map (fun rows => (header, rows))
  | none => none

/-- **A table round-trips.** -/
theorem readTable_tableText (header : List (List Char)) (rows : List (List (List Char))) :
    readTable (tableText header rows) = some (header, rows) := by
  have hheader : readCells ((tableText header rows).length + 1) (tableText header rows)
      = some (header, rows.flatMap cellsText) := by
    have hlt := length_cellsText header
    refine readCells_cellsText header _ _ ?_
    simp only [tableText, List.length_append]
    omega
  have hrows : readAllRows ((rows.flatMap cellsText).length + 1) (rows.flatMap cellsText)
      = some rows := by
    refine readAllRows_flatMap rows _ ?_
    have := length_flatMap_cellsText rows
    omega
  simp only [readTable]
  rw [hheader]
  show Option.map (fun rows => (header, rows))
      (readAllRows ((rows.flatMap cellsText).length + 1) (rows.flatMap cellsText))
    = some (header, rows)
  rw [hrows]
  rfl

/-! ## Cells that hold structure

A cell that must carry a list, a value or a provenance record carries its
canonical serialization, so the relational tables need not flatten
anything and lose nothing. -/

/-- A list of identifiers in one cell. -/
def encIds (xs : List Id) : List Char := canonEnc (idsVal xs)

/-- Reading a cell that holds a list of identifiers. -/
def decIds (s : List Char) : Option (List Id) :=
  match canonDecode s with
  | some (.list xs) => listOf idOfVal xs
  | _ => none

@[simp] theorem decIds_encIds (xs : List Id) : decIds (encIds xs) = some xs := by
  simp [decIds, encIds, idsVal, canonDecode_canonEnc]

/-- A value in one cell. -/
def encValue (v : Val) : List Char := canonEnc v

/-- Reading a cell that holds a value. -/
def decValue (s : List Char) : Option Val := canonDecode s

@[simp] theorem decValue_encValue (v : Val) : decValue (encValue v) = some v :=
  canonDecode_canonEnc v

/-- Keyed data in one cell. -/
def encFields (fs : List (List Char × Val)) : List Char := canonEnc (.obj fs)

/-- Reading a cell that holds keyed data. -/
def decFields (s : List Char) : Option (List (List Char × Val)) :=
  match canonDecode s with
  | some (.obj fs) => some fs
  | _ => none

@[simp] theorem decFields_encFields (fs : List (List Char × Val)) :
    decFields (encFields fs) = some fs := by
  simp [decFields, encFields, canonDecode_canonEnc]

/-- An optional provenance record in one cell. -/
def encProv (p : Option Prov) : List Char := canonEnc (optVal Prov.toVal p)

/-- Reading a cell that holds a provenance record. -/
def decProv (s : List Char) : Option (Option Prov) :=
  (canonDecode s).bind (optOf Prov.ofVal)

@[simp] theorem decProv_encProv (p : Option Prov) : decProv (encProv p) = some p := by
  simp [decProv, encProv, canonDecode_canonEnc]

/-- An optional certificate in one cell. -/
def encCert (c : Option Cert) : List Char := canonEnc (optVal Cert.toVal c)

/-- Reading a cell that holds a certificate. -/
def decCert (s : List Char) : Option (Option Cert) :=
  (canonDecode s).bind (optOf Cert.ofVal)

@[simp] theorem decCert_encCert (c : Option Cert) : decCert (encCert c) = some c := by
  simp [decCert, encCert, canonDecode_canonEnc]

/-- A list of records in one cell. -/
def encRecs {α : Type} (f : α → Val) (xs : List α) : List Char := canonEnc (.list (xs.map f))

/-- Reading a cell that holds a list of records. -/
def decRecs {α : Type} (g : Val → Option α) (s : List Char) : Option (List α) :=
  match canonDecode s with
  | some (.list xs) => listOf g xs
  | _ => none

theorem decRecs_encRecs {α : Type} {f : α → Val} {g : Val → Option α}
    (h : ∀ a, g (f a) = some a) (xs : List α) : decRecs g (encRecs f xs) = some xs := by
  simp [decRecs, encRecs, canonDecode_canonEnc, listOf_map h]

theorem mapM_map {α β : Type} {f : α → β} {g : β → Option α}
    (h : ∀ a, g (f a) = some a) (xs : List α) : (xs.map f).mapM g = some xs := by
  induction xs with
  | nil => rfl
  | cons a as ih =>
      simp only [List.map_cons, List.mapM_cons, h a] at ih ⊢
      rw [ih]
      rfl

/-! ## objects.csv -/

/-- The columns of `objects.csv`. -/
def objectsHeader : List (List Char) :=
  ["object_id", "kind", "name", "truth_status", "claim", "inputs", "parameters",
   "transformations", "outputs", "claim_refs", "evidence_refs", "proof_refs", "error_refs",
   "value", "provenance", "canonical_hash"].map String.toList

/-- One object as a row. -/
def objectRow (o : DomObj) : List (List Char) :=
  [o.id, o.kind, o.name, o.truth.name, o.claim, encIds o.inputs, encFields o.parameters,
   encIds o.transformations, encIds o.outputs, encIds o.claimRefs, encIds o.evidenceRefs,
   encIds o.proofRefs, encIds o.errorRefs, encValue o.value, encProv o.provenance, o.hash]

/-- One object read back from a row. -/
def objectOfRow : List (List Char) → Option DomObj
  | [id, kind, name, truth, claim, inputs, parameters, transformations, outputs, claimRefs,
     evidenceRefs, proofRefs, errorRefs, value, provenance, _hash] => do
      let truth ← Truth.ofName truth
      let inputs ← decIds inputs
      let parameters ← decFields parameters
      let transformations ← decIds transformations
      let outputs ← decIds outputs
      let claimRefs ← decIds claimRefs
      let evidenceRefs ← decIds evidenceRefs
      let proofRefs ← decIds proofRefs
      let errorRefs ← decIds errorRefs
      let value ← decValue value
      let provenance ← decProv provenance
      pure { id, kind, name, value, claim, inputs, parameters, transformations, outputs,
             claimRefs, evidenceRefs, proofRefs, errorRefs, truth, provenance }
  | _ => none

@[simp] theorem objectOfRow_objectRow (o : DomObj) : objectOfRow (objectRow o) = some o := by
  cases o
  simp [objectOfRow, objectRow]

/-- `objects.csv`. -/
def objectsTable (d : Domain) : List Char :=
  tableText objectsHeader (d.objects.map objectRow)

/-- The objects read back out of `objects.csv`. -/
def objectsOfTable (s : List Char) : Option (List DomObj) :=
  match readTable s with
  | some (_, rows) => rows.mapM objectOfRow
  | none => none

/-- **`objects.csv` is reconstructable.** -/
theorem objectsTable_recovers (d : Domain) : objectsOfTable (objectsTable d) = some d.objects := by
  simp [objectsOfTable, objectsTable, readTable_tableText, mapM_map objectOfRow_objectRow]

/-! ## proofs.csv -/

/-- The columns of `proofs.csv`. -/
def proofsHeader : List (List Char) :=
  ["proof_id", "name", "kind", "status", "source_file", "source_location", "input_refs",
   "assumptions", "procedure", "output_refs", "claim_refs", "dependencies", "certificate",
   "source", "provenance", "canonical_hash"].map String.toList

/-- One proof record as a row. -/
def proofRow (p : ProofRec) : List (List Char) :=
  [p.id, p.name, p.kind, p.status.name, p.sourceFile, p.sourceLoc, encIds p.inputRefs,
   encIds p.assumptions, p.procedure, encIds p.outputRefs, encIds p.claimRefs,
   encIds p.dependsOn, encCert p.certificate, p.source, encProv p.provenance, p.hash]

/-- One proof record read back from a row. -/
def proofOfRow : List (List Char) → Option ProofRec
  | [id, name, kind, status, sourceFile, sourceLoc, inputRefs, assumptions, procedure,
     outputRefs, claimRefs, dependsOn, certificate, source, provenance, _hash] => do
      let status ← PStatus.ofName status
      let inputRefs ← decIds inputRefs
      let assumptions ← decIds assumptions
      let outputRefs ← decIds outputRefs
      let claimRefs ← decIds claimRefs
      let dependsOn ← decIds dependsOn
      let certificate ← decCert certificate
      let provenance ← decProv provenance
      pure { id, name, kind, sourceFile, sourceLoc, inputRefs, assumptions, procedure,
             outputRefs, claimRefs, dependsOn, status, certificate, source, provenance }
  | _ => none

@[simp] theorem proofOfRow_proofRow (p : ProofRec) : proofOfRow (proofRow p) = some p := by
  cases p
  simp [proofOfRow, proofRow]

/-- `proofs.csv`. -/
def proofsTable (d : Domain) : List Char := tableText proofsHeader (d.proofs.map proofRow)

/-- The proof catalog read back out of `proofs.csv`. -/
def proofsOfTable (s : List Char) : Option (List ProofRec) :=
  match readTable s with
  | some (_, rows) => rows.mapM proofOfRow
  | none => none

/-- **`proofs.csv` is reconstructable.** -/
theorem proofsTable_recovers (d : Domain) : proofsOfTable (proofsTable d) = some d.proofs := by
  simp [proofsOfTable, proofsTable, readTable_tableText, mapM_map proofOfRow_proofRow]

/-! ## relations.csv -/

/-- The columns of `relations.csv`. -/
def relationsHeader : List (List Char) :=
  ["source_id", "relation", "target_id"].map String.toList

/-- One relation as a row. -/
def relationRow (r : Relation) : List (List Char) := [r.source, r.kind.name, r.target]

/-- One relation read back from a row. -/
def relationOfRow : List (List Char) → Option Relation
  | [source, kind, target] => do
      let kind ← Rel.ofName kind
      pure { source, kind, target }
  | _ => none

@[simp] theorem relationOfRow_relationRow (r : Relation) :
    relationOfRow (relationRow r) = some r := by
  cases r
  simp [relationOfRow, relationRow]

/-- `relations.csv`. -/
def relationsTable (d : Domain) : List Char :=
  tableText relationsHeader (d.relations.map relationRow)

/-- The relations read back out of `relations.csv`. -/
def relationsOfTable (s : List Char) : Option (List Relation) :=
  match readTable s with
  | some (_, rows) => rows.mapM relationOfRow
  | none => none

/-- **`relations.csv` is reconstructable.** -/
theorem relationsTable_recovers (d : Domain) :
    relationsOfTable (relationsTable d) = some d.relations := by
  simp [relationsOfTable, relationsTable, readTable_tableText,
    mapM_map relationOfRow_relationRow]

/-! ## domain.csv — the header table -/

/-- The columns of the domain header table. -/
def metaHeader : List (List Char) :=
  ["domain_id", "name", "version", "description", "claims", "evidence", "schemas", "errors",
   "provenance", "canonical_hash"].map String.toList

/-- The domain header as a single row. -/
def metaRow (d : Domain) : List (List Char) :=
  [d.id, d.name, d.version, d.description, encRecs Claim.toVal d.claims,
   encRecs Evidence.toVal d.evidence, encRecs Schema.toVal d.schemas,
   encRecs Err.toVal d.errors, encRecs Prov.toVal d.provenance, d.hash]

/-- `domain.csv`: the header table. -/
def metaTable (d : Domain) : List Char := tableText metaHeader [metaRow d]

/-- The domain header, the objects, the proofs and the relations, put back
together. -/
def domainOfTables (header objects proofs relations : List Char) : Option Domain :=
  match readTable header with
  | some (_, [[id, name, version, description, claims, evidence, schemas, errors, provenance,
      _hash]]) => do
      let claims ← decRecs Claim.ofVal claims
      let evidence ← decRecs Evidence.ofVal evidence
      let schemas ← decRecs Schema.ofVal schemas
      let errors ← decRecs Err.ofVal errors
      let provenance ← decRecs Prov.ofVal provenance
      let objects ← objectsOfTable objects
      let proofs ← proofsOfTable proofs
      let relations ← relationsOfTable relations
      pure { id, name, version, description, objects, relations, proofs, claims, evidence,
             schemas, errors, provenance }
  | _ => none

/-- **The relational CSV package is reconstructable**: the four tables put
back together are the domain they were cut from. -/
theorem csvTables_recover (d : Domain) :
    domainOfTables (metaTable d) (objectsTable d) (proofsTable d) (relationsTable d) = some d := by
  cases d
  simp [domainOfTables, metaTable, metaRow, readTable_tableText, objectsTable_recovers,
    proofsTable_recovers, relationsTable_recovers,
    decRecs_encRecs Claim.ofVal_toVal, decRecs_encRecs Evidence.ofVal_toVal,
    decRecs_encRecs Schema.ofVal_toVal, decRecs_encRecs Err.ofVal_toVal,
    decRecs_encRecs Prov.ofVal_toVal]

/-! ## proof-ledger.csv -/

/-- The columns of the proof ledger. -/
def ledgerHeader : List (List Char) :=
  ["object_id", "claim_id", "proof_id", "truth_status", "proof_status", "coverage",
   "canonical_hash"].map String.toList

/-- One ledger line as a row. -/
def ledgerRowCells (r : LedgerRow) : List (List Char) :=
  [r.objectId, r.claimId, r.proofId, r.truth.name,
   (match r.proofStatus with | some s => s.name | none => "--".toList),
   r.coverage.name, r.objectHash]

/-- `proof-ledger.csv`. -/
def ledgerTable (d : Domain) : List Char :=
  tableText ledgerHeader ((ledger d).map ledgerRowCells)

/-- The ledger table has exactly one line per object, plus the header. -/
theorem ledgerTable_rows (d : Domain) :
    (readTable (ledgerTable d)).map (fun p => p.2.length) = some d.objects.length := by
  simp [ledgerTable, readTable_tableText]

end Kant.Dom
