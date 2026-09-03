# XML adapter

`RequestProject/Kant/Codec/Xml.lean`; JavaScript in `web/kant-codec.mjs`.

Elements, attributes and text nodes stay distinct: a mapping entry is an
element with a `key` **attribute**, a string is a text node, and the five
XML character entities are escaped both ways.  Unknown elements have no
place to hide in a closed canonical model, so the adapter refuses them
rather than dropping them silently.

Proved: `xmlDecode_xmlEnc`, `xmlEnc_injective`, `readXUntil_xesc`.
