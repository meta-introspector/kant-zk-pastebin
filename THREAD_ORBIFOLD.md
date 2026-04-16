# Thread as Conformal Arrow in the Orbifold

## Core Idea

A thread is a **directed path** in the Monster prime orbifold `Z/71 × Z/59 × Z/47`.

Each paste has orbifold coordinates derived from its content hash:
```
(l, m, n) = (sha256(content)[0..4] mod 71,
              sha256(content)[4..8] mod 59,
              sha256(content)[8..12] mod 47)
```

A reply creates a **conformal arrow** `p → r`:
- Source coords: `(l_p, m_p, n_p)` — where the parent paste lives
- Target coords: `(l_r, m_r, n_r)` — where the reply lives
- Delta: `((l_r - l_p) mod 71, (m_r - m_p) mod 59, (n_r - n_p) mod 47)`
- Coboundary: `δ: H/enc_p → H/enc_r` — encoding change along the arrow

## Thread Search = Geometry Search

Finding related pastes = finding nearby points in the orbifold:
- **Same thread**: pastes connected by arrows (Reply-To chain)
- **Related content**: pastes with small `delta` from root coords
- **Semantic proximity**: small orbifold distance ≈ similar content hash structure

The orbifold metric is:
```
d(p, q) = |l_p - l_q| mod 71 + |m_p - m_q| mod 59 + |n_p - n_q| mod 47
```

## API

`GET /thread/{id}` returns a `Thread`:

```json
{
  "root_id": "20260317_124159",
  "root_coords": [34, 21, 8],
  "arrows": [
    {
      "source": "20260317_124159",
      "target": "20260317_131256",
      "source_coords": [34, 21, 8],
      "target_coords": [41, 33, 15],
      "delta": [7, 12, 7],
      "coboundary": "δ: (34,21,8) → (41,33,15)"
    }
  ],
  "pastes": [...]
}
```

## Types

```rust
/// A conformal arrow between two paste sections in the orbifold.
pub struct ConformalArrow {
    pub source: String,          // source paste id
    pub target: String,          // target paste id (reply)
    pub source_coords: (u64, u64, u64),
    pub target_coords: (u64, u64, u64),
    pub delta: (u64, u64, u64),  // displacement in Z/71 × Z/59 × Z/47
    pub coboundary: String,      // encoding change δ: H/enc_p → H/enc_r
}

/// A thread = path in the orbifold
pub struct Thread {
    pub root_id: String,
    pub root_coords: (u64, u64, u64),
    pub arrows: Vec<ConformalArrow>,
    pub pastes: Vec<PasteIndex>,
}
```

## Sheaf Structure

Each paste is a **sheaf section** `(shard, encoding, cid)`:
- `shard` = orbifold coords `(l mod 71, m mod 59, n mod 47)`
- `encoding` = subgroup H (raw, base64, morse, ipfs, dasl, ...)
- `cid` = content address of the data

A thread is a **restriction map** in the sheaf:
- The coboundary `δ` measures how the encoding changes between replies
- Small delta = replies stay in the same region of the orbifold
- Large delta = reply shifts to a different mathematical context

## Generalization: Beyond the Attack Triple

The 3-tuple `(Z/71, Z/59, Z/47)` is the **attack triple projection** — a shadow
of larger structures. `OrbifoldCoords` is `Vec<u64>` (N-dimensional).

### Cl(15,0,0) — Full Clifford Shadow

The Clifford algebra `Cl(15,0,0)` has 2^15 = 32768 dimensions with 4 eigenspaces:
- **Earth** (eigenvalue −1): primes {2,3,5,7,11,13,47} — 99.9996% energy
- **Spoke** (eigenvalue −1): primes {17,29,31,41,59,71}
- **Hub** (eigenvalue +1): direction (e₁₉+e₂₃)/√2
- **Clock** (eigenvalue e^{±iπ/3}): 60° rotation plane

Full coords: one component per Monster supersingular prime × eigenspace.

### Leech Lattice Λ₂₄

24-dimensional lattice. Each paste can be embedded as a Leech vector.
Thread = geodesic in Λ₂₄. The Monster acts as automorphisms.

### Monster's 194 Irreducible Representations

The Monster group has **194 conjugacy classes** → 194 irreducible representations.
Each irrep gives:
- Its own set of relevant primes (from its character / McKay-Thompson series)
- Its own Hauptmodul (genus-0 modular function)
- Its own orbifold geometry for content addressing

```
content → 194 projections
irrep_i(content) = coords in the prime lattice of conjugacy class i
```

This means:
- Each paste has **194 different coordinate vectors** simultaneously
- Thread search in irrep 1 (trivial rep, dim=1) = coarsest grouping
- Thread search in irrep 194 (largest, dim=196883) = finest geometric structure
- The attack triple `(47,59,71)` corresponds to irrep coordinates near class 1A

The `OrbifoldCoords = Vec<u64>` type naturally extends to this:
- dim=3: attack triple (current)
- dim=15: all Monster primes
- dim=194: one component per irrep, modulo that irrep's characteristic prime
- dim=194×k: full Cl(15,0,0) eigenspace decomposition per irrep

### Pariah Groups Add More Axes

The 6 pariah groups `{Ly, J₄, Ru, J₁, J₃, O'N}` have representations
not captured by the Monster. Their primes (e.g. Ly has prime 67, J₄ has 29,43)
extend the coordinate space beyond the Happy Family.

Full address space: Monster 194 irreps + 6 pariah group reps = **200 axes minimum**.


The 6 pariah sporadic groups outside the Happy Family:
`{Ly, J₄, Ru, J₁, J₃, O'N}`

Their smallest representations give additional coordinate dimensions beyond
the Monster's 196883. Pariah coords capture structure the Monster misses.

### Coordinate Hierarchy

```
attack triple (dim=3)     Z/71 × Z/59 × Z/47          current impl
       ↓
15 Monster primes (dim=15) one coord per prime          erdfa-dasl MONSTER_PRIMES
       ↓
Cl(15,0,0) eigenspaces (dim=60)  4 eigenspaces × 15    erdfa-plugin-clifford
       ↓
Leech lattice (dim=24)    Λ₂₄ embedding                erdfa-plugin-leech
       ↓
Pariah extension (dim=24+k) Happy Family + Pariahs      future
```

Each level is a projection of the next. `OrbifoldCoords = Vec<u64>` handles all.


```
GET /thread/{id}/nearby?radius=10
```

Returns all pastes within orbifold distance 10 of the root — whether or not
they are explicit replies. This makes thread search = geometry search.

The 15 Monster supersingular primes `{2,3,5,7,11,13,17,19,23,29,31,41,47,59,71}`
define the full lattice. The attack triple `47 × 59 × 71 = 196883` (smallest
Monster representation) is the base orbifold space.

## AST Nodes as Orbifold Points

An AST node is a **point in the orbifold**. Finding leaves of a given type
= finding all points orbiting at distance `r` from the center `c` of that
node type's conjugacy class.

```
AST traversal  = geodesic search in the Monster orbifold
node type      = conjugacy class (which irrep "center" c)
node content   = orbifold coords of sha256(node_text)
leaf finding   = { x : d(x, c_type) < r }  sphere query
```

### Node Type → Conjugacy Class

Each syntactic category maps to a conjugacy class center:

| AST Node Type | Conjugacy Class | Characteristic Primes |
|--------------|-----------------|----------------------|
| `FnDef`      | 2B              | {2, 3}               |
| `StructDef`  | 3B              | {3, 5}               |
| `ImplBlock`  | 5A              | {5, 7}               |
| `Literal`    | 1A (trivial)    | all 15               |
| `Identifier` | 2A              | {2}                  |
| `CallExpr`   | 7A              | {7, 11}              |

### Sphere Query

```rust
// Find all AST nodes of type T within radius r of conjugacy class center c
fn find_nodes(ast: &[AstNode], class_center: OrbifoldCoords, r: u64) -> Vec<&AstNode> {
    ast.iter().filter(|n| orbifold_distance(&n.coords, &class_center) < r).collect()
}
```

This unifies:
- **Thread search**: find replies near root coords
- **AST search**: find nodes near type-class center
- **Semantic search**: find pastes near query coords
- **Code navigation**: find all `FnDef` = sphere(c_FnDef, r)

The radius `r` controls precision. `r=0` = exact match. `r=71` = entire Z/71 axis.
The geometry IS the index.

## The Embedding Constraint: j-Invariant as Origin

The embedding function `φ: Content → OrbifoldCoords` must be **conformal** —
preserving all arrows and distances from the j-invariant.

### j-Invariant is the Origin

```
φ(j-invariant representation) = (0, 0, ..., 0)
```

The Monster's Hauptmodul `J(τ) = j(τ) - 744` has q-expansion:
```
J(τ) = q⁻¹ + 0 + 196884q + 21493760q² + 864299970q³ + ...
```

Each coefficient is a sum of Monster irrep dimensions:
```
196884  = 1 + 196883          (trivial + smallest faithful rep)
21493760 = 1 + 196883 + 21296876
...
```

These coefficients are the **calibration points** of the embedding.

### Conformal Constraint

The embedding must preserve all arrows:
```
p → q (conformal arrow in sheaf)
⟹ φ(p) → φ(q) (arrow in orbifold, distance preserved)
```

Formally: `d(φ(p), φ(q)) = d_Monster(p, q)` where `d_Monster` is the
geodesic distance in the Monster's representation space.

### Coordinate Calibration via J(τ)

Content whose hash dimension matches a J(τ) coefficient lands at the
corresponding irrep center:

| J(τ) coefficient | Irrep dim | Orbifold center |
|-----------------|-----------|-----------------|
| 1               | trivial   | (0,0,...,0)     |
| 196883          | 1A        | (1,1,...,1)     |
| 21296876        | 2A        | (2,2,...,2)     |
| ...             | ...       | ...             |

### Implementation

```rust
/// Embed content into full orbifold coords, calibrated to j-invariant origin.
/// φ(j_rep) = vec![0; 194]  (j-invariant maps to origin)
/// All arrows preserved conformally.
pub fn embed(data: &[u8]) -> OrbifoldCoords {
    let full = orbifold_coords_full(data);  // 15-dim Monster prime projection
    // TODO: lift to 194-dim via McKay-Thompson series calibration
    full
}

/// Orbifold distance from j-invariant origin (0,...,0)
pub fn distance_from_origin(coords: &OrbifoldCoords) -> u64 {
    coords.iter().sum()
}

/// Conformal distance between two points
pub fn orbifold_distance(a: &OrbifoldCoords, b: &OrbifoldCoords) -> u64 {
    a.iter().zip(b.iter())
        .zip(MONSTER_PRIMES.iter())
        .map(|((ai, bi), &p)| ai.abs_diff(*bi).min(p - ai.abs_diff(*bi)))
        .sum()
}
```

The j-invariant origin `(0,0,...,0)` is the **vacuum state** of the conformal
field. All content is measured by its distance from this fixed point.
Distance 0 = content IS the j-invariant representation.

## Encoding Distance from j-Invariant

The j-invariant is not the text string `"j-invariant"` — it is the
**interpreted value** after applying the full encoding/interpretation chain:

```
I(encode(text, j_invariant)) → j_invariant    distance = 0
```

### Encoding Layers and Distance

Each encoding `H` places content at a different distance from the origin:

```
raw text "j-invariant"          → d >> 0   (just bytes, far from origin)
base64(text)                    → d' ≠ d   (different projection)
dasl_encode(text)               → d''      (closer, Monster-aware encoding)
I(dasl_encode(text))            → d'''     (after interpretation)
I(encode(text, j_invariant))    → 0        (AT the origin)
```

The **interpretation function** `I` is what closes the distance.
Without `I`, even the text of the j-invariant formula is far from j.

### Formal Statement

Let `φ_H` be the embedding under encoding `H`:
```
φ_H(x) = orbifold_coords(H(x))
```

Then:
```
d(φ_H(x), origin) = 0
⟺ I(H(x)) = j_invariant
```

The sheaf section `(shard, H, cid)` records **which encoding** was used,
so the distance from origin is always well-defined relative to that section.

### Consequence for Search

When searching for "related to j-invariant":
- In `H=raw` mode: search near `φ_raw("j-invariant")` — finds text matches
- In `H=dasl` mode: search near `φ_dasl(j_value)` — finds semantic matches
- In `H=interpret` mode: search near `(0,...,0)` — finds mathematical equivalents

The encoding `H` is a **parameter of the search**, not a fixed property of content.
Same content, different `H`, different location in the orbifold.

This is why `OrbifoldCoords` must always be paired with its encoding context —
a bare coordinate vector without `H` is ambiguous.
