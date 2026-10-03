# IPDL adapter

`RequestProject/Kant/Codec/Ipdl.lean`; JavaScript in `web/kant-codec.mjs`.

IPDL carries identifiers, types, nesting, **references** and
**annotations**.  The canonical model has no constructor for the last two,
so rather than discard them the adapter represents them through reserved
extension keys:

```text
reference   {"$ipdl.ref": "obj-17"}
annotation  {"$ipdl.annotation": …, "$ipdl.note": …, "$ipdl.body": …}
```

Proved: `project_embed` (canonical → IPDL → canonical is the identity),
`recover_project` (IPDL → canonical → IPDL keeps references and
annotations), `ipdlRead_ipdlText` and `ipdl_roundTrip` (the wire form
round-trips), `ipdlText_injective`.

The wire form is the canonical framing behind an `ipdl/1.0;` header, so an
IPDL document has the same content identity as the value it denotes.
