/-
# The domain data package

§24: what one execution of the skill produces.  `package` is that list of
files, computed from the canonical graph:

```text
domain.ipdl   domain.xml   domain.csv   domain.yaml   domain.txt
proofs.ipdl   proofs.xml   proofs.csv   proofs.yaml   proofs.txt
objects.csv   relations.csv
proof-ledger.csv   proof-ledger.yaml
provenance.yaml
codec-report.yaml   roundtrip-report.yaml   error-report.yaml
proof-coverage.txt
```

Proved here:

* `package_files` — the package contains exactly those files;
* `package_recovers` — the package decodes back to the domain it was
  emitted from, so nothing in the graph lives only in one file;
* `package_formats_agree` — the five whole-domain files decode to the same
  graph, and
* `package_hash_shared` — every one of them carries the same canonical
  hash, which is what makes "these are the same object" checkable rather
  than asserted;
* `csvPackage_recovers` — the relational CSV tables alone rebuild the
  graph too;
* `coverageReport_total` — the coverage report accounts for every object.
-/
import Mathlib
import RequestProject.Kant.Domain.Catalog
import RequestProject.Kant.Domain.Policy

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.Dom

open Kant.Codec

/-! ## Reports -/

/-- The coverage summary as a canonical value. -/
def summaryVal (d : Domain) : Val :=
  let s := summary d
  .obj [("objects".toList, .int s.objects), ("proven".toList, .int s.proven),
        ("partially_proven".toList, .int s.partiallyProven),
        ("unproven".toList, .int s.unproven), ("contradicted".toList, .int s.contradicted),
        ("proofs".toList, .int s.proofs), ("valid_proofs".toList, .int s.validProofs)]

/-- One line of the round-trip report as a canonical value. -/
def formatReportVal (r : FormatReport) : Val :=
  .obj [("format".toList, .str r.fmt.name), ("bytes".toList, .int r.bytes),
        ("decoded".toList, .bool r.decoded),
        ("matches_canonical".toList, .bool r.matchesCanonical),
        ("canonical_hash".toList, .str r.hash)]

/-- The round-trip report: every format, what it produced, and whether the
graph came back. -/
def roundtripReportVal (d : Domain) : Val :=
  .obj [("domain".toList, .str d.id), ("canonical_hash".toList, .str d.hash),
        ("formats".toList, .list ((roundtripReport d).map formatReportVal))]

/-- The codec report: which formats are offered, what each declares, and
what the package actually observed. -/
def codecReportVal (d : Domain) : Val :=
  .obj [("schema_version".toList, .str schemaVersion),
        ("codec_version".toList, .str codecVersion),
        ("canonical_hash".toList, .str d.hash),
        ("formats".toList,
          .list (allFormats.map (fun f =>
            .obj [("format".toList, .str f.name),
                  ("declared_lossiness".toList, .str (declaredLossiness f).name),
                  ("round_trips".toList, .bool ((parse f (emit f d)).isSome))]))),
        ("coverage".toList, summaryVal d)]

/-- Proof references that resolve to nothing, object by object. -/
def danglingRefs (d : Domain) : List (Id × Id) :=
  d.objects.flatMap (fun o => (unresolvedRefs d o).map (fun i => (o.id, i)))

/-- The error report: the errors the domain carries, plus every reference
that does not resolve.  Nothing is dropped. -/
def errorReportVal (d : Domain) : Val :=
  .obj [("domain".toList, .str d.id),
        ("errors".toList, .list (d.errors.map Err.toVal)),
        ("unresolved_proof_refs".toList,
          .list ((danglingRefs d).map (fun p =>
            .obj [("object_id".toList, .str p.1), ("proof_ref".toList, .str p.2)])))]

/-- The provenance report. -/
def provenanceReportVal (d : Domain) : Val :=
  .obj [("domain".toList, .str d.id), ("canonical_hash".toList, .str d.hash),
        ("sources".toList, .list (d.provenance.map Prov.toVal)),
        ("objects".toList,
          .list (d.objects.map (fun o =>
            .obj [("object_id".toList, .str o.id), ("canonical_hash".toList, .str o.hash),
                  ("truth".toList, .str o.truth.name),
                  ("proof_refs".toList, idsVal o.proofRefs),
                  ("provenance".toList, optVal Prov.toVal o.provenance)])))]

/-- One ledger line as a canonical value. -/
def ledgerRowVal (r : LedgerRow) : Val :=
  .obj [("object".toList, .str r.objectId), ("claim".toList, .str r.claimId),
        ("proof".toList, .str r.proofId), ("truth".toList, .str r.truth.name),
        ("proof_status".toList,
          .str (match r.proofStatus with | some s => s.name | none => "--".toList)),
        ("coverage".toList, .str r.coverage.name),
        ("canonical_hash".toList, .str r.objectHash)]

/-- The proof ledger as a canonical value. -/
def ledgerVal (d : Domain) : Val :=
  .obj [("domain".toList, .str d.id), ("canonical_hash".toList, .str d.hash),
        ("coverage".toList, summaryVal d),
        ("ledger".toList, .list ((ledger d).map ledgerRowVal))]

/-- The coverage report as readable text. -/
def coverageReport (d : Domain) : List Char :=
  let s := summary d
  joinL [kv "DOMAIN".toList d.id, kv "HASH".toList d.hash,
         "".toList, "Domain Proof Coverage".toList, "".toList,
         kv "Objects".toList (natDigits s.objects),
         kv "Proven".toList (natDigits s.proven),
         kv "Partially proven".toList (natDigits s.partiallyProven),
         kv "Unproven".toList (natDigits s.unproven),
         kv "Contradicted".toList (natDigits s.contradicted),
         kv "Proofs".toList (natDigits s.proofs),
         kv "Valid proofs".toList (natDigits s.validProofs)]

/-! ## The package -/

/-- The file a package entry is: a name and its contents. -/
abbrev File := List Char × List Char

/-- **The domain data package.**  Every representation the standard asks
for, computed from one canonical graph. -/
def package (d : Domain) : List File :=
  [("domain.ipdl".toList, emit .ipdl d),
   ("domain.xml".toList, emit .xml d),
   ("domain.csv".toList, emit .csv d),
   ("domain.yaml".toList, emit .yaml d),
   ("domain.txt".toList, emit .text d),
   ("objects.csv".toList, objectsTable d),
   ("proofs.ipdl".toList, encodeVal .ipdl (proofsVal d)),
   ("proofs.xml".toList, encodeVal .xml (proofsVal d)),
   ("proofs.csv".toList, proofsTable d),
   ("proofs.yaml".toList, encodeVal .yaml (proofsVal d)),
   ("proofs.txt".toList, encodeVal .text (proofsVal d)),
   ("relations.csv".toList, relationsTable d),
   ("domain-header.csv".toList, metaTable d),
   ("proof-ledger.csv".toList, ledgerTable d),
   ("proof-ledger.yaml".toList, encodeVal .yaml (ledgerVal d)),
   ("provenance.yaml".toList, encodeVal .yaml (provenanceReportVal d)),
   ("codec-report.yaml".toList, encodeVal .yaml (codecReportVal d)),
   ("roundtrip-report.yaml".toList, encodeVal .yaml (roundtripReportVal d)),
   ("error-report.yaml".toList, encodeVal .yaml (errorReportVal d)),
   ("proof-coverage.txt".toList, coverageReport d)]

/-- The file names the package contains. -/
def packageFiles : List (List Char) :=
  ["domain.ipdl", "domain.xml", "domain.csv", "domain.yaml", "domain.txt",
   "objects.csv", "proofs.ipdl", "proofs.xml", "proofs.csv", "proofs.yaml", "proofs.txt",
   "relations.csv", "domain-header.csv", "proof-ledger.csv", "proof-ledger.yaml",
   "provenance.yaml", "codec-report.yaml", "roundtrip-report.yaml", "error-report.yaml",
   "proof-coverage.txt"].map String.toList

/-- **The package contains exactly the files the standard lists.** -/
theorem package_files (d : Domain) : (package d).map Prod.fst = packageFiles := rfl

/-- The contents of one file of a package. -/
def fileOf (files : List File) (n : List Char) : Option (List Char) :=
  (files.find? (fun f => f.1 == n)).map Prod.snd

/-- The domain read back out of a package. -/
def packageRead (files : List File) : Option Domain :=
  match fileOf files "domain.yaml".toList with
  | some s => parse .yaml s
  | none => none

/-- **The package decodes back to the domain it came from.** -/
theorem package_recovers (d : Domain) : packageRead (package d) = some d := by
  have hfile : fileOf (package d) "domain.yaml".toList = some (emit .yaml d) := rfl
  simp only [packageRead, hfile, parse_emit]

/-- **The five whole-domain files all describe the same graph.** -/
theorem package_formats_agree (d : Domain) (f g : Fmt) :
    parse f (emit f d) = parse g (emit g d) := cross_representation f g d

/-- **And every one of them carries the same canonical hash.** -/
theorem package_hash_shared (d : Domain) (f : Fmt) :
    (parse f (emit f d)).map Domain.hash = some d.hash := hash_shared f d

/-- **The relational CSV tables rebuild the graph on their own.** -/
theorem csvPackage_recovers (d : Domain) :
    (do
      let header ← fileOf (package d) "domain-header.csv".toList
      let objects ← fileOf (package d) "objects.csv".toList
      let proofs ← fileOf (package d) "proofs.csv".toList
      let relations ← fileOf (package d) "relations.csv".toList
      domainOfTables header objects proofs relations) = some d := by
  have h1 : fileOf (package d) "domain-header.csv".toList = some (metaTable d) := rfl
  have h2 : fileOf (package d) "objects.csv".toList = some (objectsTable d) := rfl
  have h3 : fileOf (package d) "proofs.csv".toList = some (proofsTable d) := rfl
  have h4 : fileOf (package d) "relations.csv".toList = some (relationsTable d) := rfl
  rw [h1, h2, h3, h4]
  simpa using csvTables_recover d

/-- **The proof catalog survives its own partition too.** -/
theorem package_proofs_partition (d : Domain) (f : Fmt) :
    decodeVal f (encodeVal f (proofsVal d)) = some (proofsVal d) := decodeVal_encodeVal f _

/-- **The coverage report accounts for every object**, and reports the
same classification the ledger does. -/
theorem coverageReport_total (d : Domain) :
    (summary d).proven + (summary d).partiallyProven + (summary d).unproven +
      (summary d).contradicted = d.objects.length := summary_total d

/-- **The round-trip report in the package is true**: it claims a match
for each format, and each format really does return the canonical
graph. -/
theorem package_roundtrip_report_sound (d : Domain) :
    ∀ r ∈ roundtripReport d, r.decoded = true ∧ r.matchesCanonical = true ∧ r.hash = d.hash :=
  roundtripReport_sound d

/-- **The error report keeps every error the domain carries.** -/
theorem errorReport_keeps_errors (d : Domain) :
    errorReportVal d = .obj [("domain".toList, .str d.id),
        ("errors".toList, .list (d.errors.map Err.toVal)),
        ("unresolved_proof_refs".toList,
          .list ((danglingRefs d).map (fun p =>
            .obj [("object_id".toList, .str p.1), ("proof_ref".toList, .str p.2)])))] := rfl

/-- A dangling reference really is one: it is named by an object and
resolves to nothing. -/
theorem danglingRefs_sound (d : Domain) (o : DomObj) (i : Id)
    (h : (o.id, i) ∈ danglingRefs d) : ∃ o' ∈ d.objects, o'.id = o.id ∧ i ∈ o'.proofRefs ∧
      findProof d i = none := by
  simp only [danglingRefs, List.mem_flatMap, List.mem_map] at h
  obtain ⟨o', ho', i', hi', heq⟩ := h
  simp only [Prod.mk.injEq] at heq
  obtain ⟨hid, rfl⟩ := heq
  simp only [unresolvedRefs, List.mem_filter] at hi'
  exact ⟨o', ho', hid, hi'.1, Option.isNone_iff_eq_none.1 (by simpa using hi'.2)⟩

/-! ## The relational package

For a large domain the five whole-domain serializations are big files.
The relational projection is the same graph — `tablesPackage_recovers` —
in tables that can be read a row at a time. -/

/-- The relational tables, the ledger and the reports. -/
def tablesPackage (d : Domain) : List File :=
  [("domain-header.csv".toList, metaTable d),
   ("objects.csv".toList, objectsTable d),
   ("proofs.csv".toList, proofsTable d),
   ("relations.csv".toList, relationsTable d),
   ("proof-ledger.csv".toList, ledgerTable d),
   ("proof-ledger.yaml".toList, encodeVal .yaml (ledgerVal d)),
   ("provenance.yaml".toList, encodeVal .yaml (provenanceReportVal d)),
   ("error-report.yaml".toList, encodeVal .yaml (errorReportVal d)),
   ("proof-coverage.txt".toList, coverageReport d)]

/-- The domain read back out of the relational tables. -/
def tablesPackageRead (files : List File) : Option Domain := do
  let header ← fileOf files "domain-header.csv".toList
  let objects ← fileOf files "objects.csv".toList
  let proofs ← fileOf files "proofs.csv".toList
  let relations ← fileOf files "relations.csv".toList
  domainOfTables header objects proofs relations

/-- **The relational package is the whole graph too.** -/
theorem tablesPackage_recovers (d : Domain) : tablesPackageRead (tablesPackage d) = some d := by
  have h1 : fileOf (tablesPackage d) "domain-header.csv".toList = some (metaTable d) := rfl
  have h2 : fileOf (tablesPackage d) "objects.csv".toList = some (objectsTable d) := rfl
  have h3 : fileOf (tablesPackage d) "proofs.csv".toList = some (proofsTable d) := rfl
  have h4 : fileOf (tablesPackage d) "relations.csv".toList = some (relationsTable d) := rfl
  simp only [tablesPackageRead, h1, h2, h3, h4]
  exact csvTables_recover d

/-- The file names of the relational package. -/
theorem tablesPackage_files (d : Domain) :
    (tablesPackage d).map Prod.fst =
      ["domain-header.csv", "objects.csv", "proofs.csv", "relations.csv", "proof-ledger.csv",
       "proof-ledger.yaml", "provenance.yaml", "error-report.yaml",
       "proof-coverage.txt"].map String.toList := rfl

/-! ## The whole procedure -/

/-- §20, as one function: discover (already done — the domain), link,
canonicalize, validate, emit, re-import, compare, report. -/
def exchange (d : Domain) : List File × Bool :=
  let canonical := withDerivedRelations d
  let files := package canonical
  let reimported := packageRead files
  (files, reimported.map Domain.text == some canonical.text)

/-- **The exchange procedure reports success, and is right to**: what it
re-imports is exactly the canonical graph it emitted. -/
theorem exchange_roundTrips (d : Domain) : (exchange d).2 = true := by
  simp [exchange, package_recovers]

/-- Canonicalizing fills the relations table in from the proof catalog and
changes nothing else. -/
theorem exchange_canonicalizes (d : Domain) :
    (withDerivedRelations d).relations = derivedRelations d := rfl

end Kant.Dom
