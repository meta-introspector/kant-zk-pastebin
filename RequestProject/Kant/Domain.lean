/-
# The domain data codec and proof emission skill

The codec layer (`Kant.Codec`) moves one proof object between formats.
This layer takes a whole *domain* — its data objects, the claims made
about them, the proofs that establish them and the relations between all
of those — emits it into every representation, and keeps every emitted
object attached to the proof that establishes it.

| Module | Covers | Guarantees |
|---|---|---|
| `Kant.Dom.Model` | objects, proofs, claims, evidence, relations, schemas, errors, provenance | the canonical graph, its round trip, its content hash |
| `Kant.Dom.Emit` | the five representations and the readable text form | every one round-trips, all agree, all carry one hash |
| `Kant.Dom.Ledger` | resolution, coverage, the proof ledger, the two-way walk | a `PROVEN` row always cites a `VALID` proof that resolves |
| `Kant.Dom.Table` | the relational CSV projections | the tables alone rebuild the graph |
| `Kant.Dom.Policy` | truth transitions and error reconciliation | no silent upgrade, no silent downgrade, no discarded error |
| `Kant.Dom.Catalog` | a scanned corpus as a domain | the catalog is well formed; a `sorry` is never `PROVEN` |
| `Kant.Dom.Package` | the deliverable file set and the reports | the package decodes back to the domain it came from |
| `Kant.Dom.Tests` | the worked example and the golden vectors | every claim above, checked on concrete data |
-/
import RequestProject.Kant.Domain.Model
import RequestProject.Kant.Domain.Emit
import RequestProject.Kant.Domain.Ledger
import RequestProject.Kant.Domain.Table
import RequestProject.Kant.Domain.Policy
import RequestProject.Kant.Domain.Catalog
import RequestProject.Kant.Domain.Package
import RequestProject.Kant.Domain.Tests
