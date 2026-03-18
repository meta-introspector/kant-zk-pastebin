# Pending Changes — kant-pastebin

## Summary

Add sheaf theory module, ChatGPT prompt splitter, and eRDFa metadata injection into paste format.

## Commit message

```
feat: sheaf module, ChatGPT splitter, eRDFa paste metadata

- Add sheaf.rs: M→H→E mapping with DASL types, Cl(15,0,0) eigenspaces,
  encoding types mapped to Monster supersingular primes, Section struct
  with escaped and live RDFa output, restriction maps between sections
- Inject Sheaf header and eRDFa metadata into paste file format on create
- Add "✂️ Split" button to paste form and view pages, sends text to
  splitter via localStorage
- Add ChatGPT prompt splitter to static-pastebin: splits large text into
  framed chunks with part numbering for multi-message LLM input
- Add splitter UI with chunk size selector (5k/10k/15k/25k chars)
- Add eRDFa system objects doc describing the knowledge hypergraph
- Update systemd service nix store path
```

## Files changed

| File | Status | Description |
|------|--------|-------------|
| `src/sheaf.rs` | NEW | Sheaf theory: DaslType, EigenSpace, Encoding enums; Section struct with DASL addressing and RDFa output; restriction_map; sheaf_header |
| `src/handlers.rs` | MOD | Nav link to splitter, Split button on form+view, sendToSplitter() JS, sheaf header+RDFa in paste format |
| `src/lib.rs` | MOD | `pub mod sheaf` |
| `src/main.rs` | MOD | `mod sheaf` |
| `static-pastebin/app.js` | MOD | splitForChat(), copyChunk(), copyAllChunks(), localStorage cross-app sharing |
| `static-pastebin/index.html` | MOD | Splitter section with chunk size selector |
| `static-pastebin/style.css` | MOD | .chunk styling |
| `kant-pastebin.service` | MOD | Updated nix store path |
| `20260317_erdfa_system_objects.txt` | NEW | eRDFa system objects doc |

## Build status

- Compiles: ✅ (48 warnings, all dead-code in sheaf.rs — expected for new module)
- Errors: 0

## Architecture notes

The sheaf module models each paste as a section of a sheaf over the Monster group:
- **M** (Monster object) → orbifold coordinates via `dasl::orbifold_coords`
- **H** (subgroup) → encoding type (Raw, Base64, Morse, Split, QR, etc.)
- **E** (data) → content-addressed via DASL CID

Each encoding maps to a Monster supersingular prime (2,3,5,7,11,13,47,59,71).
Eigenspace classification uses Cl(15,0,0) algebra (Earth/Spoke/Hub/Clock).
DASL addresses pack type, eigenspace, Hecke index, Bott index, and hash into 64 bits.

The splitter enables cross-app text sharing between the pastebin and the
static splitter page via localStorage, supporting the sneakernet workflow.
