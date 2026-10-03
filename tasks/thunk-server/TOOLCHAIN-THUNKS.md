# Compilers are thunks

**Date:** 2026-10-03 · **Status:** proposed · **Companion to** [IPFS-IPDL.md](IPFS-IPDL.md), [WASM.md](WASM.md)

## The claim

`lake`, `cargo` and `nix` are not infrastructure the thunk system calls out to.
They are **thunks**, content-addressed like any other, and a thunk that needs
one *refers* to one rather than invoking whatever is on `$PATH`.

This follows from [IPFS-IPDL.md](IPFS-IPDL.md) rather than being an addition to
it. That document split the formats into three groups and put `lean`, `rust` and
`nix` in the third: *inputs* a toolchain turns into an artifact. If the input is
referenced and pinned, then **the thing that interprets it is in the same
category** — it is just an input that happens to consume other inputs.

So the unit is uniform:

```
thunk = { id, format, bytes, refs, state, schedule }
                       │     └─ other thunks: sources AND toolchains
                       └─ the artifact
```

A Lean thunk's refs are the `.lean` source *and* `lake`. A Rust thunk's refs are
`Cargo.toml` *and* `cargo` *and* the `rustc` version. Nothing special.

## The tree already half-does this, which is the evidence

`flake.nix` pins **four** inputs, all as `github:owner/repo/<40-hex sha>`:

```
github:NixOS/nixpkgs/0954f7ee2f6bb3dc7d4e3d0d8bcb8fd4bde4cfc5
github:numtide/flake-utils/11707dc2f618dd54ca8739b309ec4fc024de578b
github:ipetkov/crane/8833b7dc3c7426ce1110ed6fed31b6f63d74f2dc
github:numtide/system-manager/3dd7dbe51bb2232b7b51295a022c627c99fe14dd
```

**`nixpkgs` is the compiler source.** Everything else — `flake-utils`, `crane`,
`system-manager` — is tooling. The pin that decides what compiles the Rust code
is that one sha, so the compiler is already content-addressed *as a flake input*
rather than as an IPDL ref. That is a presentation difference, not a structural
one, and it is why this is worth unifying rather than replacing.

I first wrote "`pkgs.rustPlatform` resolves to a concrete Rust toolchain" here.
**That was wrong — `rustPlatform` does not appear in this `flake.nix` at all.**
I asserted a mechanism from a different file and only caught it by grepping after
writing the claim.

Two gaps in what the tree does today:

- **`nixpkgs` is pinned, the derived toolchain is not.** A store path's hash
  depends on the whole nixpkgs tree at that sha, the build platform, and the
  substituters. Reproducible in practice, *not* content-addressed by
  construction. A ref would pin the artifact directly.
- **The Lean side is absent from this repo.** No `lakefile`, no
  `lean-toolchain`, no Lean input in `flake.nix`. `RequestProject/Wasm/*.lean`
  and `Kant/Codec/*.lean` appear only in comments, as if they were local.

## The Lean side exists — it is just not here

That second gap is a gap in *this checkout*, not in the work. At
`/home/mdupont/aristotle-manager-src/splitter-engine/` there are **30,096
`.lean` files**, and the splitter has been run on itself:

```
117204 declarations in environment
32 seed declarations in requested modules
2761 declarations in dependency closure
2761 declaration files written to ./split-self-test
2761 flake.nix files written
dag.json written (117204 lines)
```

**That is the compiler-as-thunk pattern, already working.** Every declaration
became a `flake.nix` — a build unit with its dependencies as refs — and
`doc-index.md` records **175 independent flakes**. A sample:

```lean
-- Split/absurd.lean
import Mathlib
-- spec: absurd : forall {a : Prop} {b : Sort.{v}}, a -> (Not a) -> b
def absurd : ... := fun {a} {b} (h₁ : a) (h₂ : Not a) => False.rec ... (h₂ h₁)
```

`import Mathlib` with a `-- spec:` header naming the type. So the shape already
exists and already runs: **a source file, its dependencies, and a per-declaration
build.** What is missing is only the naming — nothing calls these "thunks" or
gives them IPDL refs, because they predate the vocabulary.

One caveat from reading their own numbers: `TEST_RESULTS.md` claims **2,761**
declarations and 2,761 `flake.nix` files, but the `find … -name "*.lean"` output
in the same document says **2,759**. Two files are accounted for in one count
and not the other, and nothing says why. Small, but it is exactly the kind of
discrepancy that a content-addressed scheme would make impossible — which is a
small argument for the whole idea rather than against these results.

This also sharpens the recursion question. I claimed the Lean chain "bottoms out
in something small enough to check by hand" as a *hypothetical*. If the Lean
toolchain itself is formalised, and the kernel is reachable by reflection from
`aristotle`, then it is not hypothetical — the bottom of the chain is already a
kernel, and a kernel is checkable by a kernel. That is a very different trust
root from a pinned binary, and it makes the recommendation below wrong in the
conservative direction.

## The recursion, and where it stops

This is the part worth being careful about, because it terminates in one of only
two places.

```
Lean source ──> lake ──> Lean toolchain ──> (C toolchain) ──> (bootstrap) ──> ?
Rust source ──> cargo ──> rustc ──> LLVM ──> C++ toolchain ──> (linker) ──> ?
wasm module ──> ? nothing
```

**Option A — stop at a pinned binary.** Every toolchain in the chain is an IPDL
ref naming a sha, and the deepest one is an opaque blob nobody re-derives. This
is what nix does with binary caches: reproducible, and the bottom of the chain is
a trust assumption rather than a derivation.

**Option B — stop at a verified kernel.** The chain bottoms out in something
small enough to check. `web/kant_kernel.wasm` is this shape, and the kernel
reflection work in `aristotle` is what makes it reachable.

**This document originally treated B as a hypothesis.** It is not. The Lean
formalizations — the toolchain, Lean-in-Lean, the patched kernel — mean the
bottom of the Lean chain *is* a kernel, and a kernel is checkable by a kernel.
So for Lean the recursion terminates in something verifiable, not in an opaque
binary. That is a real difference from the Rust side, where `rustc` is a hundred
megabytes of C++ and nobody is going to hand-verify it.

**It still does not stop at wasm.** A wasm module needs no compiler, but
*producing* one from Lean source needs `lake`, and `lake` was built by a C
compiler. wasm moves the recursion rather than ending it. Worth saying plainly,
because "wasm, therefore no toolchain" is the tempting wrong conclusion — and it
is the conclusion this document would have drawn two revisions ago.

So the honest shape is a **two-root trust model**, not one:

| chain | terminates in | verified by |
|---|---|---|
| Lean → wasm → kernel | a kernel | the kernel, by reflection in `aristotle` |
| Rust → wasm / dylib | a pinned `rustc` store path | nothing; it is an assumption |

A thunk's refs should say **which root it stands on**, because "content
addressed" means different assurance on each side. A Lean thunk can be checked
end to end. A Rust thunk is only pinned.

## Why this matters for the swarm

If the toolchain is a ref, then a peer resolving a Lean thunk is doing real work:
fetch the source, fetch the pinned `lake`, build, verify the artifact hash. Three
consequences:

1. **Resolution is expensive and must be cacheable.** Artifacts are small (the
   wasm kernel is 799 bytes); builds are not. The cache is the artifact store
   keyed by the thunk id, and the id covers the refs, so a cached artifact is
   correct for that id by construction.

2. **A ref that names a version is unresolvable once yanked.** Already flagged in
   [IPFS-IPDL.md](IPFS-IPDL.md), but sharper now: with toolchains as refs, this
   applies to `lake` too. If a toolchain is pinned by *version*, toolchains rot
   exactly like `core2 0.4.0` did. **Toolchain refs must name shas.** A version is
   a convenience for humans; the ref is what gets resolved.

3. **Two peers can legitimately disagree about a build** while agreeing on every
   id — if the toolchain differs. That is the strongest argument for putting refs
   in the id: same id should mean same bytes *and* same build, or "content
   addressed" is quietly false.

## The trust root question, stated once

Every design above assumes some starting point. There are exactly three
candidates, and picking one is a decision, not an implementation detail:

| root | what you trust | cost | where |
|---|---|---|---|
| pinned binary sha | the binary cache, and whoever filled it | simplest; opaque | rustc |
| nixpkgs sha (today) | the nixpkgs tree + platform + substituters | in use; reproducible, not content-addressed | both |
| verified kernel | a kernel checked by a kernel | strongest; mostly built | Lean |

**Recommendation, revised.** I first wrote "keep option A for toolchains, option
B only for anything feeding a witness" — conservative advice written without
accounting for the Lean formalizations. Given a formalised Lean toolchain and
kernel reflection in `aristotle`, that understates what is available.

The better split:

- **Lean thunks: verify end to end.** The kernel is reachable by reflection, so a
  Lean thunk's whole chain — source, toolchain, artifact — can be checked rather
  than trusted. This should be the *default* and the thing the swarm prefers.
- **Rust thunks: pin, and say so.** `rustc` is not going to be hand-verified, and
  the honest move is to mark the ref as *pinned, not verified* rather than let
  "content addressed" imply equal assurance on both sides.
- **Anything feeding a witness: kernel-verified regardless of language.** A claim
  computed by unverified `rustc` and checked by the Lean kernel is only as good
  as the weaker link, so such thunks want the verified root or none.

That gives the swarm a real property to advertise: **"this thunk is verified"
is a stronger statement than "this thunk is pinned", and the refs should be able
to distinguish them.**

## Phases

These slot under [IPFS-IPDL.md](IPFS-IPDL.md) phase 5 rather than beside it.

| # | phase | done when |
|---|---|---|
| A | Toolchain refs exist as a type | an IPDL `ref` can name a toolchain, distinct from a source |
| B | nix resolver handles a toolchain | `iRef("github:NixOS/nixpkgs/<sha>")` → the rust toolchain artifact |
| C | Artifacts cached by thunk id | resolving twice does not rebuild |
| D | Lean toolchain introduced | a `lake` ref exists; `lakefile` + `lean-toolchain` land |

**Phase B is the one that proves the idea.** If a toolchain can be fetched and
pinned through the same resolver that handles sources, then "compilers are
thunks" stops being a slogan and becomes a mechanism — and it needs no Lean work
to get there.

## Related

[THUNK-CYCLE.md](THUNK-CYCLE.md) is the loop these three feed: sops on every
thunk, `apis + sops + args` ⇒ results, results as new thunks or cached values
with history, a lens an expensive thunk over other thunks' results, and a schedule
constrained by measured budgets.

## Open

- **Is `nixpkgs` a ref, or the mechanism that resolves refs?** Today it is both,
  which is circular: a resolver built on nix cannot itself be pinned by an IPDL
  ref without bootstrapping. Probably acceptable — one trusted bootstrap step —
  but it should be written down rather than discovered later.
- **Store paths are not content addresses.** A nix store path encodes its input
  *derivations*, not its output hash, so mapping one to an IPDL ref needs the
  output hash (`nix hash path`) and not the path itself. Unverified whether that
  is available offline.
- **Nothing here has been resolved over a network.** Every claim is from reading
  `flake.nix`, `Cargo.toml` and `scripts/kant-codec.mjs`. No resolver exists.