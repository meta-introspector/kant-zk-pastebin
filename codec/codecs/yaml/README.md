# YAML adapter

`RequestProject/Kant/Codec/Yaml.lean`; JavaScript in `web/kant-codec.mjs`.

The human-readable projection, in flow style, with double-quoted scalars
and the usual five escapes.  Keys keep their order and duplicates are
preserved, because the canonical model treats a mapping as an ordered list
of entries.

Proved: `yamlDecode_yamlEnc`, `yamlEnc_injective`, `readQuoted_esc`.
