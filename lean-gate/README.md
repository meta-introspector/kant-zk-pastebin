# The Lean proof gate

`RequestProject/` here is the smallest Lean development that proves the
pastebin's extracted kernel correct, with **no Mathlib**. It is the closure of
`Wasm/KernelSpec.lean`: thirteen modules, ~3,000 lines, importing nothing
outside core Lean 4.

```
npm run verify                # runs scripts/lean-proofs.mjs among the core suites
scripts/lean-proof-gate.sh    # just the gate, ~10.5s cold / ~2.7s warm
```

## What it proves

`Wasm/KernelSpec.lean` carries one theorem per exported wasm function, tying
the Lean definition to the wasm expression the kernel actually evaluates:

```
Lean definition  =  wasm expression  =  emitted .wasm function
```

The middle link is `Expr.exec_compile` (the compiled code evaluates the
expression); the right-hand one is `Encode.module` (the bytes in
`web/kant_kernel.wasm` are the binary form of that code); the left-hand one is
what this tree proves. `web/wasm-test.mjs` checks the other end — that the
emitted binary computes the 59 golden vectors. Between them, "the wasm kernel
is correct" stops being a phrase.

`gokujo check` runs five gates and fails on any of them: the module graph and
its build order, the build, a hole scan (`sorry` / `admit` / `native_decide`),
and an axiom audit. The audit currently reports 181 declarations resting on
`propext`, `Classical.choice` and `Quot.sound` — that is, nothing beyond what
core Lean 4 allows.

## Why it is here and not only on `origin/feature/lean`

The Lean tree is not on this branch. It lives on `origin/feature/lean` at
`a3cd85b`, which `scripts/lean-codec-types.mjs` already reads for the codec
checks. But that tree cannot be built here:

* `lean-toolchain` pins `leanprover/lean4:v4.28.0`. There is no `elan` on this
  machine and the `lean`/`lake` on `PATH` are 4.30.0, so the pinned toolchain
  has to be named explicitly (see `scripts/lean-proof-gate.sh`).
* With Mathlib on `LEAN_PATH`, **a single `import Mathlib` did not finish
  elaborating in 401s**, and the 26-module closure produced zero `.olean`
  files in 560s. Eighteen of those 26 modules imported Mathlib.

So this directory is that tree with Mathlib taken out. `lean-gate/RequestProject`
is not vendored copy-paste; every change is listed below.

## What the Mathlib removal actually involved

The substitutions, and what each one is really for:

| Mathlib | core Lean 4.28 | why |
| --- | --- | --- |
| `interval_cases n <;> rfl` | `(show ∀ i : Fin 16, … from by decide) ⟨n, h⟩` | enumerating a bounded `Nat` needs either Mathlib's `interval_cases` or `decide` over `Fin n`, which core *does* have a `Decidable` instance for |
| `by norm_num` on closed facts | `by decide` | same kernel reduction, without the tactic |
| `by positivity` | `by decide` | it was only ever closing `0 < 2 ^ n` |
| `List.sum_map_const` | a three-line induction | it is a `Batteries`/Mathlib lemma; the statement is two lines |
| `List.Perm.foldl_eq` + a `RightCommutative` instance | `foldl_eq_xorAll` + `xorAll_perm`, proved here | Mathlib's version wants a typeclass; xor is commutative and associative, which is what those two lemmas say |
| `Nat.Prime` | a local `IsPrime` bounded by `Fin p` | Mathlib's is not in core, and the `Fin` bound is what makes the claim `decidable` |
| `List.prod` | a local `listProd` | `List.prod` is `foldr (· * ·) 1`; only `Mathlib` exports it |
| `Nat.pair` | see below | the old theorem was **false** |
| `split_ifs` | `by_cases` + `simp only [ite_true, ite_false]`, or `rcases Nat.lt_or_ge` | `split_ifs` is Mathlib; core has `split` and `by_cases` |
| `nlinarith` | `Nat.mul_lt_mul_of_lt_of_lt` plus two `decide`d literals | the only products in the way are `a * a` with `a < 2 ^ 31`, which is one multiplication lemma and one closed fact |

Things that turned out **not** to be needed: `Nat.xor_lt_two_pow`,
`Nat.and_two_pow_sub_one_eq_mod`, `List.Pairwise`, `List.mergeSort_perm`,
`List.pairwise_mergeSort`, `decide_eq_true_eq`, `List.all_eq_true`,
`List.length_take` and `List.nodup_cons` are all in core 4.28. Two of the three
axioms the audit reports (`propext`, `Classical.choice`, `Quot.sound`) are
core's, and `decide` pulls in `Lean.ofReduceBool` / `Lean.trustCompiler` in
some configurations but not here.

## Two theorems that were false

Both were in `Kant/Sneakernet.lean` and `Wasm/KernelSpec.lean`. Neither could
have compiled; that they are here at all is the strongest evidence that this
part of the Lean tree was never built.

**`eval_cantorPairE` claimed the kernel computes `Nat.pair`.** It does not.
Mathlib's `Nat.pair a b = if a ≤ b then 2 * b * (b + 1) + a else …`, and
`cantorPairE` computes `[a < b]·(b² + a) + [a ≥ b]·(a² + a + b)`. At `a = 0`,
`b = 1` those are 4 and 1. The theorem now states what the kernel does, in
`cantorPair`, and its docstring records that the old claim was wrong. The
`nlinarith` that was supposed to bridge the two could not have: `2 * b * (b + 1)`
is not linear.

**`reassemble_perm` is false as stated.** It assumes `fs₁.Perm fs₂` and
`(fs₁.map Frame.seq).Nodup` and concludes `reassemble fs₁ = reassemble fs₂`.
Take `f₁ = ⟨5, 5, [1]⟩`, `f₂ = ⟨5, 5, [2]⟩`, `g = ⟨9, 9, [3]⟩`, `fs₁ = [f₁, g]`,
`fs₂ = [f₂, g]`. Both hypotheses hold — the sequence numbers are 5 and 9 — but
`mergeSort` is stable and nothing orders `f₁` against `f₂`, so `reassemble fs₁`
is `[1, 3]` and `reassemble fs₂` is `[2, 3]`. The original proof leaned on
`List.inj_on_of_nodup_map`, which cannot deliver it: a nodup *sequence* list
says nothing about distinct frames that share a sequence number.

Those two theorems, and `reassemble_frames_perm` which depends on them, are
omitted from this tree with the counterexample recorded in
`Kant/Sneakernet.lean`. They are not needed by the closure of `KernelSpec.lean`.
Restating `reassemble_perm` correctly needs a strict hypothesis — distinct
frames carry distinct sequence numbers — and proving it needs a
strict-monotonicity argument over the sorted list that core Lean does not have
ready. That is a separate piece of work, and it is not hidden: the omission is
a comment, in the file, with the counterexample.

## Layout

```
RequestProject/
  Kant/Bytes.lean          hex, FNV-1a, digest       -- no Mathlib
  Kant/Credits.lean                                  -- already had none
  Kant/Dasl.lean           0xDA51 addresses, orbifold, merge algebra
  Kant/Sneakernet.lean     framing under a size cap
  Kant/Stego.lean          least-significant-bit embedding
  Wasm/Leb128.lean Syntax.lean Encode.lean           -- the wasm object language
  Wasm/Semantics.lean Decode.lean Kernel.lean
  Wasm/Extraction.lean
  Wasm/KernelSpec.lean     one theorem per exported function  <- the proof
  lean-toolchain           v4.28.0, the version the gate compiles with
```

`.gokujo/` is the build cache and is gitignored.

## Why it can sit in `npm run verify`

Measured, on this machine, with the load average the gate runs under:

| | cold | warm |
| --- | --- | --- |
| `gokujo check` (13 modules, no Mathlib) | **10.4 / 10.7 / 10.8 s** | **2.65 s** |
| the same closure *with* Mathlib on `LEAN_PATH` | **> 560 s, 0 oleans produced** | — |

That ratio is the entire reason this tree exists in this shape, and it is why
the gate is affordable enough to run on every verify rather than on demand.