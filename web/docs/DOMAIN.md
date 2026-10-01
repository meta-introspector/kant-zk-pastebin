# The domain data codec and proof emission skill

**This is not only a proof interchange codec.**  It takes a *domain*,
enumerates its data objects, finds the proofs that establish them, emits
the whole thing into every requested representation, and keeps every
emitted object attached to the proof that establishes it.

```text
                    DOMAIN
                      │
          ┌───────────┴───────────┐
     DOMAIN DATA              PROOF CATALOG
          └───────────┬───────────┘
                CANONICAL MODEL
                      │
       ┌──────┬───────┼───────┬──────┐
     IPDL    XML     CSV     YAML   TEXT
       └──────┴───────┼───────┴──────┘
               PROVENANCE / HASH
                      │
                PROOF REFERENCES
```

Everything below with a name in `code font` is a theorem in
`RequestProject/Kant/Domain/`, checked by `lake build` with no `sorry` and
no axioms beyond `propext`, `Classical.choice` and `Quot.sound`.  The
`#guard` block at the end of `Domain/Tests.lean` runs the worked example
through all of it at compile time.

## 1. The canonical unit

`Kant.Dom.DomObj` is the domain object of §2: `id`, `kind`, `name`,
`value`, `claim`, `inputs`, `parameters`, `transformations`, `outputs`,
`claim_refs`, `evidence_refs`, **`proof_refs`**, `error_refs`, a truth
status and provenance.  `Kant.Dom.Domain` is the whole graph: objects,
relations, proofs, claims, evidence, schemas, errors, provenance.

`Domain.ofVal_toVal` says the canonical model loses nothing;
`Domain.toVal_injective` and `Domain.eq_of_text_eq` say the canonical text
determines the domain, which is what makes `Domain.hash` a content
identity rather than a label.

## 2. Proof is a first-class relationship

A domain object never carries the string `proof: "proved"`.  It carries
identifiers that resolve to `Kant.Dom.ProofRec`s, and a proof record says
what it consumes (`input_refs`), what it produces (`output_refs`), what it
establishes (`claim_refs`), what it depends on (`dependencies`), whether
it holds (`status`) and what certificate stands behind it.

`proven_points_at_a_proof` — an object counts as `PROVEN` only when one of
the proofs it names *resolves in the catalog* and reports `VALID`.

## 3. Truth statuses and proof statuses

```text
PROVEN  DERIVED  VERIFIED  ASSERTED  IMPORTED  INFERRED
UNRESOLVED  CONTRADICTED  INVALID
```

```text
VALID  INVALID  PARTIAL  FAILED  UNKNOWN  CONFLICT
```

`truthName_injective` and `pstatusName_injective`: the names are distinct,
so `ASSERTED` cannot travel as `PROVEN` by accident.  A certificate also
carries how much evidence it is — `evidence_levels_distinct` keeps *a
proof exists*, *a machine checked it* and *somebody reproduced it* apart.

## 4. Five representations, one graph

| Representation | Written by | Read by |
|---|---|---|
| IPDL | `emit .ipdl` | `parse .ipdl` |
| XML | `emit .xml` | `parse .xml` |
| CSV | `emit .csv` | `parse .csv` |
| YAML | `emit .yaml` | `parse .yaml` |
| TEXT | `emitText` | `parseText` |

* `parse_emit` — every representation round-trips;
* `cross_representation` — `decode(IPDL) = decode(XML) = decode(CSV) =
  decode(YAML) = decode(TEXT)`;
* `hash_shared` — every one of them carries the same canonical hash, so
  five files that look nothing alike can be *shown* to be one object;
* `same_domain_iff` — and two files hold the same domain exactly when
  their decoded graphs agree.

The raw-text form is not second class.  `emitText` writes the readable
rendering of §13 — domain, objects, claims, proofs, inputs, outputs,
relations, diagnostics, provenance — length-prefixed, followed by the
canonical block, so the file a person reads is the file a machine decodes
(`parseTextFull_emitText` returns *both*).

Emission may be partitioned: `partition_recovers` says the header, the
objects, the proofs and the relations, emitted separately in any format
and read back, rebuild the domain exactly.

## 5. Relational CSV

§11 asks for tables rather than one flattened sheet.
`objects.csv`, `proofs.csv`, `relations.csv` and `domain-header.csv` are
proper relational projections with quoted, variable-width rows
(`readCells_cellsText`, `readTable_tableText`).  Cells that must hold
structure hold the canonical serialization of that structure, so nothing
is flattened away: `objectsTable_recovers`, `proofsTable_recovers`,
`relationsTable_recovers`, and `csvTables_recover` — the four tables alone
rebuild the graph.

## 6. Coverage and the proof ledger

`coverage` classifies each object `PROVEN`, `PARTIALLY_PROVEN`,
`UNPROVEN` or `CONTRADICTED` from the graph alone, so the classification
is reproducible by anyone holding the package.

* `coverage_proven_iff` — the exact condition for `PROVEN`;
* `summary_total` — the four classes partition the objects, so the
  coverage report accounts for every one of them;
* `ledger_proven_sound` — a ledger line that says `PROVEN` cites a proof
  that resolves and reports `VALID`;
* `ledger_unproven_has_no_proof` — and a line that cites nothing does not
  say `PROVEN`;
* `ledger_stable`, `summary_stable` — the ledger and the summary computed
  from any emitted representation are the ones of the canonical graph.

## 7. The walk in both directions

For a well-formed package (`Kant.Dom.Wf`: unique identifiers, references
that resolve, proofs and objects that name each other, and no `PROVEN`
without a `VALID` proof):

```text
DATA → PROOF → INPUTS
             → OUTPUTS → DATA
```

`data_to_proof`, `proof_to_inputs`, `proof_to_outputs`, and
`traversal_round_trip`, which walks data → proof → output → data and lands
back on the object it started from.  `proven_not_bare` — a proven object
always names at least one proof.  `derived_proves` and `derived_input` put
those edges in the relations table both ways.

## 8. No silent claims

`Kant.Dom.step` is the only way a truth status changes, and it takes an
event.

* `no_silent_upgrade` — a value that was not already `PROVEN` becomes
  `PROVEN` only through a validation event naming a proof record that is
  in the catalog and reports `VALID`;
* `assertion_never_upgrades` — asserting, importing or inferring moves
  nothing towards `PROVEN`;
* `refusal_recorded` — a refused upgrade leaves the status alone and
  attaches an error;
* `downgrade_is_reported` — `PROVEN → INVALID` or `PROVEN → CONTRADICTED`
  always emits a fatal error.

## 9. Errors are reconciled, not discarded

`reconcileInt` is the worked example of §21: a cell that arrived as text
where the schema declares an integer.  `repair_keeps_the_error` — the
record still says what was expected, what arrived and what was done;
`resolved_revalidates` — a coercion that works revalidates and says with
what; `unresolved_stays_visible` — one that does not stays in the package,
not recoverable, with no value; `repair_is_not_a_proof` — and a repair
never moves a truth status.

## 10. The proof catalog of a corpus

`Kant.Dom.catalog` turns a scanned corpus into a domain: one object per
declaration, one proof record and one claim per proof, and the relations
implied by the catalog.

* `catalog_wf` — for a corpus with unique names whose dependencies stay
  inside it, the catalog is a well-formed graph, so §7's walk works on it;
* `sorried_not_proven`, `nonstandard_axioms_not_proven` — a declaration
  that still contains a `sorry`, or that rests on a non-standard axiom, is
  never `PROVEN`;
* `sorried_has_no_certificate` — and there is no certificate to point at;
* `catalog_coverage_proven` — a sorry-free declaration checked against the
  standard axioms is `PROVEN`, with a `VALID` machine-checked record.

## 11. The package

Two programs run the eight steps of §20 on this project's own corpus:

```bash
lake exe emitdomain domain/corpus-scan.kant RequestProject   # discover
lake exe packdomain domain/corpus-scan.kant domain           # link … report
```

or `sh scripts/domain-package.sh <outdir> <module-prefix>` for both.  The
first needs the compiled environment; the second needs only the scan file,
which is itself a canonical value that round-trips
(`scan_file_roundTrip`).  `packdomain` writes:

```text
domain.ipdl   domain.xml   domain.csv   domain.yaml   domain.txt
proofs.ipdl   proofs.xml   proofs.csv   proofs.yaml   proofs.txt
objects.csv   relations.csv   domain-header.csv
proof-ledger.csv   proof-ledger.yaml
provenance.yaml
codec-report.yaml   roundtrip-report.yaml   error-report.yaml
proof-coverage.txt
```

`package_files` says the package is exactly that list; `package_recovers`
says it decodes back to the domain it came from; `csvPackage_recovers`
says the CSV tables do too; `package_roundtrip_report_sound` says the
round-trip report in the package is *true* and not merely written down;
and `exchange_roundTrips` says the whole procedure — canonicalize, emit,
re-import, compare — reports success and is right to.

Discovery is not taken on trust from the source text.  The emitter loads
the compiled environment and asks the kernel which axioms each declaration
actually used; `sorryAx` among them is what makes a declaration
`UNRESOLVED` and its proof `PARTIAL`.  So in the emitted package `PROVEN`
means *the Lean kernel checked it against the standard axioms*.

`packdomain --tables` writes the relational projection only — the same
graph (`tablesPackage_recovers`) in files that stay small for a corpus of
thousands of declarations.

`packdomain --shard-size=N` emits the corpus as a partition instead: the
declarations are cut into shards of `N`, each shard is made `Closed` by
dropping the dependencies that leave it, and each is emitted, re-imported
and compared on its own.  The shards' counts and canonical hashes go into
`shards.csv`, and the edges cut at the boundaries into
`cross-shard-deps.csv`, so the partition loses nothing.  This is what
makes a corpus of thousands of declarations *checkable* and not merely
emittable: the decoders recurse over their input, so one multi-megabyte
table exhausts the runtime stack, while fifteen shards of four hundred
declarations all round-trip.

The checked-in `domain/` directory is the package for this project;
`domain/README.md` says what each file is.  For the whole corpus — 5 997
declarations — `domain/full-corpus/proof-coverage.txt` reports 2 667
objects `PROVEN` with a `VALID` machine-checked proof record, none
partially proven, and 3 330 `ASSERTED` definitions that claim nothing
more, and `domain/full-corpus/shards/` holds the whole corpus emitted as
fifteen shards, every one of which was read back and compared
(`RECOVERED` in `shards.csv`), with the shard counts adding back up to
the same 5 997 / 2 667 / 3 330.

## 12. The final invariant

```text
DATA → PROOF        data_to_proof
PROOF → INPUTS      proof_to_inputs
PROOF → OUTPUTS     proof_to_outputs
OUTPUT → DATA       traversal_round_trip
```

and, across the representations,

```text
decode(IPDL) = decode(XML) = decode(CSV) = decode(YAML) = decode(TEXT)
             = the canonical graph               cross_representation
same canonical hash in every file                hash_shared
```

which is what makes "the forms are proven" a property that can be
checked rather than a sentence in a document.
