/-
# The standard proof codec

The transport and reconciliation layer: one canonical proof object, and
adapters to and from every supported format.  No external format is the
canonical representation; each is an adapter to the same semantic object,
so integrating `N` systems costs `N` adapters rather than `N²`.

| Module | Covers | Guarantees |
|---|---|---|
| `Kant.Codec.Val` | the canonical value tree, deterministic serialization | stable field order, injective encoding, content identity |
| `Kant.Codec.Model` | statuses, errors, inputs, outputs, provenance, the proof object | vocabularies round-trip, the canonical text determines the object |
| `Kant.Codec.Yaml` | the human-readable projection | round trip, injectivity |
| `Kant.Codec.Xml` | elements, attributes, text nodes | round trip, injectivity |
| `Kant.Codec.Csv` | the tabular projection with parent links | round trip, and honest about flat rows |
| `Kant.Codec.Ipdl` | references and annotations in reserved keys | nothing discarded, round trip both ways |
| `Kant.Codec.RawText` | raw text as a first-class input, format detection | original bytes preserved, a failed parse is not an invalid proof |
| `Kant.Codec.Reconcile` | structured differences, verdicts, conflict resolution | exact comparison, no silent merge |
| `Kant.Codec.Exchange` | envelopes, import/export, schema versions, conformance | lossless claims are true, the definition of done |
| `Kant.Codec.Tests` | the specification's required test suite | every listed case, checked |
-/
import RequestProject.Kant.Codec.Val
import RequestProject.Kant.Codec.Model
import RequestProject.Kant.Codec.Yaml
import RequestProject.Kant.Codec.Xml
import RequestProject.Kant.Codec.Csv
import RequestProject.Kant.Codec.Ipdl
import RequestProject.Kant.Codec.RawText
import RequestProject.Kant.Codec.Reconcile
import RequestProject.Kant.Codec.Exchange
import RequestProject.Kant.Codec.Tests
