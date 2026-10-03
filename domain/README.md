# The domain data package

This directory is the skill of [`docs/DOMAIN.md`](../docs/DOMAIN.md) run on
this project's own domain: the Lean corpus of `RequestProject`.

Every file here was written by the encoders proved correct in
`RequestProject/Kant/Domain/`, from one canonical domain graph.

## What a domain object is here

One declaration of the corpus: its statement, where it lives, what it
consumes, and — if it is a theorem — the proof record that establishes it.
The truth status is not taken from the source text.  The scanner loads the
compiled environment and asks the kernel which axioms each declaration
actually used:

| in the package | means |
|---|---|
| `truth_status = PROVEN`, `proof_status = VALID` | the kernel checked it, and only against `propext`, `Classical.choice`, `Quot.sound`, `Lean.ofReduceBool`, `Lean.trustCompiler` |
| `truth_status = UNRESOLVED`, `proof_status = PARTIAL` | `sorryAx` is among the axioms it used — there is no certificate at all |
| `truth_status = ASSERTED` | a definition, a structure, an instance: a stipulation, not a claim, so nothing claims it is proven |

Everything the kernel holds from this project's modules is included,
including the declarations the elaborator generated (equation lemmas,
derived instances, and so on).  They are real constants of the
environment, and they are labelled exactly like any other.

## Layout

```text
corpus-scan.kant          the discovery step for the whole project, 5 997 declarations
full-corpus/
  proof-ledger.csv        the ledger for all 5 997
  proof-coverage.txt      its coverage summary
  shards/                 the whole corpus as a verified partition, 15 shards of 400
    shards.csv            one line per shard: counts, canonical hash, round-trip result
    cross-shard-deps.csv  the 23 358 dependency edges that cross a shard boundary
    shard-000/ … shard-014/
                          the relational package of each shard
model/                    the complete package for one scope, all twenty files
  corpus-scan.kant        the scan it was built from, 425 declarations
  domain.ipdl  domain.xml  domain.csv  domain.yaml  domain.txt
  proofs.ipdl  proofs.xml  proofs.csv  proofs.yaml  proofs.txt
  objects.csv  relations.csv  domain-header.csv
  proof-ledger.csv  proof-ledger.yaml
  provenance.yaml
  codec-report.yaml  roundtrip-report.yaml  error-report.yaml
  proof-coverage.txt
```

`model/` is the package for the declarations of
`RequestProject.Kant.Domain.Model` — a scope small enough that all five
whole-domain serializations are readable files.  The tool re-imported
every one of them and compared the result to the canonical graph before
it exited:

```text
re-imported: the package decodes back to the canonical graph
relational tables: rebuild the canonical graph
```

## Coverage

`full-corpus/proof-coverage.txt`:

```text
Objects: 5997
Proven: 2667
Partially proven: 0
Unproven: 3330
Contradicted: 0
Proofs: 2667
Valid proofs: 2667
```

Every theorem of the corpus is `PROVEN` with a `VALID`, machine-checked
proof record; nothing is partially proven, because nothing carries a
`sorry`; the 3 330 unproven objects are the definitions, structures and
instances, which are `ASSERTED` and claim nothing more.

## Reproducing it

```bash
lake exe emitdomain domain/corpus-scan.kant RequestProject          # discover
lake exe packdomain domain/corpus-scan.kant domain/full --tables    # tables only
lake exe packdomain domain/model/corpus-scan.kant domain/model      # every representation
```

The first program is the only one that needs the compiled environment;
the second is ordinary compiled Lean and reads the scan file, which is
itself a canonical value (`Kant.Dom.scan_file_roundTrip`).

The five whole-domain serializations of the *whole* corpus are around
90 MB and take a large amount of memory to build, which is why the
checked-in complete package is the smaller scope.

For the whole corpus the emission is *partitioned* instead, which §8 of
the standard allows:

```bash
lake exe packdomain domain/corpus-scan.kant domain/full-corpus/shards --shard-size=400
```

Each shard is a corpus in its own right — the dependencies that leave it
are removed from its declarations, so it is `Closed` and its catalog is
well formed (`Kant.Dom.catalog_wf`) — and each shard is emitted,
re-imported and compared on its own before the tool exits.  All fifteen
report `RECOVERED` in `shards.csv`, and the shard counts add back up to
the whole: 5 997 objects, 2 667 proven, 3 330 unproven, 2 667 valid
proofs.  Nothing is lost at the boundaries: the 23 358 dependency edges
that cross one are written out as `cross-shard-deps.csv`, and the
unpartitioned scan keeps them all.

The reason to partition rather than emit one file per table is the
decoder, not the encoder: the parsers recurse over the input, so reading
a single table of several megabytes back exhausts the runtime stack.
Emitting a table that large still works, but then the round trip could
only be argued from `Kant.Dom.tablesPackage_recovers` rather than
observed, and this package prefers what it can check.

## Reading the ledger

```text
object_id,claim_id,proof_id,truth_status,proof_status,coverage,canonical_hash
```

`proof_id` resolves in `proofs.csv`, whose `output_refs` names the object
back, and whose `input_refs` names what the proof consumed — which is the
walk `DATA → PROOF → INPUTS / OUTPUTS → DATA` that
`Kant.Dom.traversal_round_trip` proves always closes.
