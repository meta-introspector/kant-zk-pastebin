# CSV adapter

`RequestProject/Kant/Codec/Csv.lean`; JavaScript in `web/kant-codec.mjs`.

CSV is a *tabular projection*, not a pretence that proofs are flat.  The
convention is the one the specification recommends:

```text
object_id,object_type,field,value,value_type,parent_id
```

with one row per node in preorder, a child count on every container, and
a parent link on every child — which is what makes the nesting
recoverable.

Proved: `csvDecode_csvEncode`, `csvEncode_injective`, and `flatRows_lossy`
— the honest statement that a table of scalar rows *without* the counts
and parent links could not distinguish two different values.
