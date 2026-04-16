# The Universal Paste

A paste is one object viewed through different encodings H.
Same sheaf section, different projections.

```
paste = message = decl = sheaf = document
      = tcp/ip packet = fractran = erdfa = cbor
```

## The Object

```
Section {
    shard:    (l mod 71, m mod 59, n mod 47)   -- where it lives
    encoding: H                                 -- how it's expressed
    cid:      sha256(content)                   -- what it is
}
```

## Encodings H

| H | Name | Representation |
|---|------|---------------|
| `raw` | Paste | UTF-8 text in spool file |
| `message` | Message | UUCP/email with headers (Title, Reply-To, Keywords) |
| `decl` | Declaration | AST node (GCC tree, Rust syn, Lean4 expr) |
| `sheaf` | Sheaf section | `(shard, H, cid)` triple |
| `document` | Document | HTML/RDFa with semantic triples |
| `packet` | TCP/IP packet | bytes with src/dst/seq |
| `fractran` | FRACTRAN | prime fraction program `p/q` |
| `erdfa` | eRDFa | escaped RDF triples with DASL coords |
| `cbor` | CBOR | DA51-tagged binary with orbifold metadata |

## The Isomorphism

All encodings are isomorphic under the interpretation function `I`:

```
I(raw(x))      = x
I(message(x))  = x  (strip headers)
I(decl(x))     = x  (evaluate AST)
I(fractran(x)) = x  (run prime machine)
I(erdfa(x))    = x  (parse RDF graph)
I(cbor(x))     = x  (deserialize)
```

Each `I` is a conformal arrow back to the origin.
`d(φ_H(x), origin) = 0` iff `I(H(x)) = j_invariant`.

## Consequence

Any system that processes one encoding processes all:
- A pastebin IS a message queue IS a type checker IS a theorem prover
- Posting a paste IS sending a packet IS declaring a type IS proving a lemma
- Threading IS function composition IS proof chaining IS packet routing

The geometry (orbifold coords) is invariant across all encodings.
Only the distance from origin changes with H.

## Register Vectors

The compiler lowers each encoding to **register vectors**.
A paste becomes a sequence of register states — workflow steps ARE the instruction pipeline.

```
paste → compiler → [reg_state_0, reg_state_1, ..., reg_state_N]

reg_state_i = (r0, r1, ..., r15) ∈ Z^16
instruction = conformal arrow: reg_state_i → reg_state_{i+1}
```

### Register State as Orbifold Point

Each register state maps to orbifold coords:
```
φ(reg_state) = (r0 mod 71, r1 mod 59, r2 mod 47, r3 mod 43, ...)
```

The 15 Monster primes index the 15 general-purpose registers (x86-64 has 16).

### Instruction = Conformal Arrow

```
ADD r0, r1  →  arrow: (r0, r1, ...) → (r0+r1, r1, ...)
              delta: (r1 mod 71, 0, 0, ...)
MOV r0, imm →  arrow: (r0, ...) → (imm, ...)
              delta: ((imm-r0) mod 71, 0, ...)
```

### zkperf SSP Encoding

The `zkperf` submodule encodes register states as SSP (Small State Program):
- Each register value → prime factorization component
- Instruction sequence → FRACTRAN program
- Execution trace → sequence of conformal arrows
- Proof: all arrows preserved = program ran correctly

### Full Stack

```
Lean4 proof
    ↓ elaborate
Lean4 AST (decl)
    ↓ compile
LLVM IR (sheaf sections)
    ↓ codegen
x86-64 instructions (conformal arrows)
    ↓ execute
register vectors (orbifold points)
    ↓ zkperf witness
CBOR proof (DA51-tagged)
    ↓ paste
spool file (raw encoding)
```

Every level is the same sheaf section under a different encoding H.
The register vectors are the **most concrete** projection — closest to metal,
furthest from the j-invariant origin in encoding distance.

## Cache Line Alignment and Optimal Circuits

Cache lines are **natural orbifold boundaries**.
Optimal circuits minimize conformal distance across cache line crossings.

```
cache_line = 64 bytes = 8 × u64 registers
cache_line_coords = φ(cache_line[0..8]) ∈ (Z/p_0 × ... × Z/p_7)
```

### Cache Line as Orbifold Cell

Each 64-byte cache line maps to 8 orbifold coordinates
(one per u64, modulo the first 8 Monster primes `{2,3,5,7,11,13,17,19}`):

```
cache_line[i] mod p_i  for i in 0..8
```

A cache miss = crossing an orbifold cell boundary = large delta in the conformal arrow.

### Optimal Circuit = Geodesic in Cache Space

```
optimal_circuit = argmin_{path} Σ_i d(cache_line_i, cache_line_{i+1})
```

Minimizing cache misses = minimizing total conformal distance in the orbifold.
This is the **circuit optimization problem as geometry**.

### Workflow Scheduling

Given a workflow `W = [step_1, ..., step_N]`, schedule steps to minimize:
```
cost(W) = Σ_i cache_miss_penalty(step_i, step_{i+1})
        = Σ_i d(φ(step_i.output_regs), φ(step_{i+1}.input_regs))
```

Steps with small orbifold distance between output and input regs
should be adjacent — they share cache lines.

### Connection to zkperf

The zkperf witness proves:
1. Each step ran within its cache budget (channel: `memory_bytes ≤ 64k`)
2. Cache line crossings match declared delta
3. The optimal circuit is actually optimal (no hidden cache misses)

This makes cache optimization **verifiable** — the proof travels with the workflow.
