# Renderer Plugin Architecture

## Core Principle

State is mathematical (orbifold coords, DASL CIDs, sheaf sections).
Rendering target is just a plugin — swap without touching core logic.

## Layer Stack

```
erdfa-dasl / erdfa-sheaf        pure math state, no UI deps
        ↓
zos-plugin-interface            ZosPlugin trait
  - to_html()                   server-side render (actix)
  - to_wasm()                   client WASM binary
  - to_api()                    JSON REST
  - to_fractran()               prime fraction program
  - to_a11y()                   accessibility proof
  - to_semantic()               escaped RDFa triples
  - to_audio()                  SSML
  - to_tactile()                Braille + haptic
        ↓
renderer plugins (each standalone crate):
  actix-renderer                current pastebin (to_html server-side)
  dioxus-renderer               web/desktop WASM via Dioxus
  tauri-renderer                native desktop
  ratatui-renderer              TUI
```

## Bare Repos

| Crate | Bare |
|-------|------|
| `zos-plugin-interface` | `/mnt/data1/git/solana.solfunmeme/zos-plugin-interface.git` |
| `solfunmeme-dioxus` | `/home/mdupont/projects/solfunmeme-dioxus` (no bare yet) |

## Integration with solfunmeme-dioxus

`solfunmeme-dioxus` uses `inventory::collect!(PluginRegistration)` where each plugin
provides a `render: fn() -> Element` (Dioxus component).

Each pastebin view (paste, browse, gallery, stego) becomes a `PluginRegistration`
with `PluginCategory::Data`. The dioxus app picks them up automatically.

The pastebin backend (actix) stays unchanged — dioxus calls the REST API.

## Next Steps

1. Add `zos-plugin-interface` as flake input to pastebin
2. Implement `ZosPlugin` for `Paste` model (to_html, to_api, to_semantic already exist)
3. Create `dioxus-renderer` crate wrapping paste views as dioxus components
4. Wire into `solfunmeme-dioxus` via `inventory::collect!`
