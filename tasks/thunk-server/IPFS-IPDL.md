# IPDL over Nix, nora, crates and GitHub

**Date:** 2026-10-03 · **Status:** proposed · **Companion to** [WASM.md](WASM.md)

## The shape

A thunk payload is not one format. It is a **content-addressed blob plus a
typed reference**, and the reference is an **IPDL document** — the codec that is
already in this tree at `scripts/kant-codec.mjs`, transcribed from
`RequestProject/Kant/Codec/*.lean` and pinned by 91 checks in
`scripts/codec-test.mjs`.

```
thunk = { id, format, bytes, refs, state, schedule }
                    │      │     └─ IPDL doc: what this came from
                    │      └─ wasm | js | lean | rust | nix | …
                    └─ sha256 of bytes, full 64-hex
```

Formats that are *sources* rather than artifacts — **lean**, **rust**, **nix** —
are referenced, not embedded. The IPDL document says what to fetch and pins it;
the thunk carries the built bytes once resolved. That distinction is the whole
design, and it is why IPDL is the right wrapper rather than a manifest format
invented for this.

## IPDL already has the two features this needs

From `scripts/kant-codec.mjs`:

```js
const iRef   = (target)   => ({ t: "ref",   target: String(target) });
const iAnnot = (key, note, body) => ({ t: "annot", key, note, body });
```

A **`ref`** carries an opaque target string, and an **`annot`** attaches a note
to any body. That is a dependency edge and a human-readable explanation of it.
Measured, just now:

```
iAnnot('dep', 'a dependency', iRef('github:NixOS/nixpkgs/0954f7ee…'))
  -> ipdl/1.0;O3;16;$ipdl.annotationS3;dep10;$ipdl.noteS12;a dependency10;$ipdl.bodyO1;9;$ipdl.refS61;github:…
  -> ref round-trips:            true
  -> hash stable across round-trip: true
  -> different target, different hash: true
```

And `valHash` (`kant-codec.mjs:180`) already returns a **full 64-hex digest**,
which is exactly what `asWitness` (`web/kant-libp2p.mjs:112`) requires — and
exactly what [WASM.md](WASM.md) phase 1 says thunk ids should be. The codec and
the swarm already agree on what a witness is. Nobody designed that; it is just
true.

## The gap: `ref.target` is stored, never resolved

`grep` the codec and `ref` appears in exactly three places — the constructor, the
projector, and the reader (`kant-codec.mjs:37`, `:466`, `:475`). **Nothing
resolves a target.** IPDL can carry `github:NixOS/nixpkgs/0954f7ee…` perfectly
well and has no idea it means anything.

So the wrapper is not a new codec. It is a **resolver** over an existing one:

```
iRef("github:NixOS/nixpkgs/0954f7ee…")   -> fetch -> bytes -> sha256 -> the IPDL ref is satisfied
```

Each backend already speaks content addressing, which is what makes this tractable:

| backend | target form | already pinned? |
|---|---|---|
| nix | `github:owner/repo/<40-hex sha>` | yes — every input in `flake.nix:17-23` is a full sha |
| GitHub | `github:owner/repo/<40-hex sha>` | same form |
| crates.io | `registry = "nora"` / crates.io | `Cargo.lock` pins the sha256 of the `.crate` |
| nora | `registry = "nora"` — `solana.solfunmeme.com` | same |

Every one of these is *already* a content address. The wrapper does not need to
invent addressing; it needs to translate each backend's spelling into one
`valHash`.

## Four formats, three categories — do not treat them alike

This is where I would push back on the framing. "js, wasm, lean, rust, nix and
more" is one list, but the formats fall into three groups with genuinely
different properties, and the difference decides who is allowed to execute them.

**1. Executable, self-contained: `wasm`.** 799 bytes, zero imports, 21 exports.
Cannot reach the host. Safe by construction.

**2. Executable, host-reaching: `js`, and a Rust dylib.** `js` is the case
[WASM.md](WASM.md) already covers: `server/thunk.mjs` hands `require` into its
sandbox, and once the loader works a thunk spawning a process returns the uid.
A Rust `cdylib` loaded via an FFI shim is the same shape — it has the ambient
authority of the host. **These need a capability label, not a format tag.**

**3. Not executable: `lean`, `rust`, `nix` — these are *inputs*.** A `.lean`
file is not a program; it is a description that a toolchain turns into one. Same
for `Cargo.toml` and `flake.nix`. So:

- the thunk's `bytes` is the **resolved artifact**, not the source
- the IPDL `ref` names the **source and its pin**
- a resolver maps `lean` → olean/wasm via `lake`, `rust` → a built artifact via
  cargo, `nix` → a store path via nix

This is the useful part of the idea. Right now `feature/big-merge` cannot build
because `core2 0.4.0` is yanked — an upstream registry decision, invisible to
anyone reading `Cargo.toml`. With IPDL refs, **that becomes a content-addressed
pin in a document anyone can read**, and the swarm can carry the replacement.

## What the swarm actually gains

Today a dependency is a *name* resolved against a *live registry*. Two peers
running "the same" thunk can be running different bytes, because `version = "*"`
in `Cargo.toml:24` means whatever the registry served that day.

With IPDL refs, `refs` is part of what `valHash` covers — and I verified the hash
is stable across serialization and changes when the target changes. So:

- **two thunks with the same id are running the same bytes *and* the same
  dependency pins.** That is a stronger claim than [WASM.md](WASM.md) phase 1
  makes, and it is the actual reason to prefer IPDL over a bespoke manifest.
- a yanked upstream becomes a resolvable question ("what satisfies this ref?")
  rather than an unbuildable branch.

## Phases

| # | phase | done when |
|---|---|---|
| 0 | [`WASM.md`](WASM.md) phase 0 | the thunk loader works; sandbox policy decided |
| 1 | Content addressing | `id` is the full `valHash` of the payload bytes |
| 2 | `refs` in the thunk | `refs` is an IPDL doc, hashed with the definition |
| 3 | **One** resolver: nix | `iRef("github:owner/repo/<sha>")` → bytes → verified sha |
| 4 | One more: crates | `iRef("nora:core2/0.4.0")` → `.crate` bytes → sha |
| 5 | Build inputs | `lean` / `rust` / `nix` refs resolve to *artifacts*; the source never becomes the payload |
| 6 | Capability labels | `wasm` vs host-reaching formats distinguished, swarm refuses the latter by default |

**Phase 3 alone is worth doing** and touches nothing else. Nix is the best first
backend because its targets are already `github:owner/repo/<40-hex sha>` — there
is no version resolution to get wrong, just a fetch and a hash check. It also
turns `flake.nix:17-23` from prose config into a document the swarm can carry.

Phases 4–5 are where the real complexity lives, because crates and nix *do*
resolve versions and a resolver that disagrees with cargo is worse than none.

## Related

[TOOLCHAIN-THUNKS.md](TOOLCHAIN-THUNKS.md) takes the third group further: the
toolchains that consume `lean`/`rust`/`nix` inputs are themselves thunks. Because
the Lean toolchain is formalised and the kernel is reachable by reflection in
`aristotle`, the Lean chain terminates in something **verifiable**; the Rust
chain only terminates in a pinned `rustc`. So "verified" and "pinned" are
different claims and a ref should be able to distinguish them.

## Related

[THUNK-CYCLE.md](THUNK-CYCLE.md) is the loop these three feed: sops on every
thunk, `apis + sops + args` ⇒ results, results as new thunks or cached values
with history, everything a lens, and a schedule constrained by measured budgets.

## Open

- **Does `refs` belong in the thunk id?** I argue yes — two peers with the same
  payload but different pins are not running the same thing. That makes the id
  hash over `{ bytes, refs }`, not `bytes`. It also means a ref that resolves to
  different bytes *changes the id*, which is correct but surprising. Worth an
  explicit decision before phase 2.
- **Yanked crates have no content address to fall back to.** If `core2 0.4.0` is
  gone, the resolver cannot honour a ref naming it. Does a ref name a *version*
  (unresolvable, reproducible only while it exists) or a *sha* (resolvable, but
  the manifest has to know it)? I lean sha, which means publishing resolved refs
  as a second artifact.
- **The Lean side.** `RequestProject/Kant/Codec/*.lean` is the real definition;
  anything added here must land there too or the two drift. `scripts/kant-codec.mjs`
  says it is an "unverified transcription", and the 91 checks pin it against
  golden vectors — but not against Lean itself in this tree.
- **Unverified by me:** every claim here is from reading `kant-codec.mjs`,
  `flake.nix`, `Cargo.toml` and running the codec. Nothing has resolved a ref
  over a network, and no resolver exists yet.

## Honest summary of what is real

Already built and working: the IPDL codec with `ref`/`annot`, a full-length
`valHash`, a 16 KiB swarm transport byte-identical in JS and Rust, and a
content-addressed wasm payload at 799 bytes.

Not built: any resolver, any capability labelling, and the thunk loader itself.
The gap between those two lists is [WASM.md](WASM.md) phase 0.