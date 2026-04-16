# JS/WASM Deobfuscator via Monster Orbifold

## Concept

Every JS AST node is a point in the Monster group orbifold. Obfuscation is conformal noise — deobfuscation is geodesic projection back to canonical coordinates.

## Pipeline

```
JS source → oxc parse → AST
         ↓
    AST node → Monster coords (15-dim)
         ↓
    Fuzz 100% path coverage → trace all branches
         ↓
    Perf trace → timing/memory/entropy per path
         ↓
    Value trace → register snapshots at each coord
         ↓
    Conformal field → geodesic clustering
         ↓
    Canonical names from j-invariant distance
```

## Encoding Layers

Each JS artifact encoded at multiple granularities:

1. **Bit** - raw bytes, cache line aligned (64B = 8 coords)
2. **Byte** - UTF-8 boundaries
3. **Token** - lexer output (oxc tokenizer)
4. **Sentence** - statement/expression
5. **Paragraph** - function body
6. **Heading** - function signature
7. **Document** - module/file
8. **Directory** - package structure
9. **Host** - npm registry / CDN
10. **URL** - import specifier
11. **Escaped** - URI encoding
12. **RDFa** - semantic annotations
13. **CBOR** - binary serialization
14. **Ontology** - type system (Monster irreps)

## Workflow Capture

For each JS file:

```rust
struct JsArtifact {
    source: String,
    ast_coords: Vec<OrbifoldCoords>,      // AST node → coords
    fuzz_paths: Vec<ExecutionPath>,       // 100% coverage traces
    perf_trace: Vec<ChannelMeasurement>,  // timing/memory/entropy
    value_trace: Vec<RegisterSnapshot>,   // all register states
    conformal_field: ConformalArrow,      // source → optimized
    canonical_names: HashMap<u32, String>, // coord → deobfuscated name
    encodings: EncodingStack,             // bit → ontology
}

struct ExecutionPath {
    branch_coords: Vec<OrbifoldCoords>,
    coverage_bitmap: Vec<u8>,
    cost: u64,  // conformal distance
}

struct RegisterSnapshot {
    coords: OrbifoldCoords,
    regs: [u64; 8],  // cache line state
    stack: Vec<u64>,
}

struct EncodingStack {
    bit: Vec<u8>,
    token: Vec<Token>,
    statement: Vec<Statement>,
    function: Vec<Function>,
    module: Module,
    package: Package,
    url: Url,
    rdfa: RdfGraph,
    cbor: Vec<u8>,
    ontology: MonsterType,
}
```

## Fuzzing Strategy

1. **Parse** - oxc AST with coords
2. **Instrument** - inject coverage probes at each branch
3. **Fuzz** - AFL++ / libFuzzer with orbifold-guided mutations
4. **Trace** - capture perf counters + register state
5. **Cluster** - geodesic distance groups similar paths
6. **Canonicalize** - j-invariant origin = simplest form

## Deobfuscation

Obfuscated code has high conformal distance from origin. Deobfuscation:

```rust
fn deobfuscate(ast: &Program) -> Program {
    let coords = ast_to_coords(ast);
    let origin = vec![0u64; 15];  // j-invariant
    let geodesic = find_geodesic(&coords, &origin);
    coords_to_ast(&geodesic)
}
```

Variable names chosen by nearest Monster irrep:

```rust
fn canonical_name(coords: &[u64]) -> String {
    let irrep_idx = coords[0] % 194;  // 194 Monster irreps
    MONSTER_IRREPS[irrep_idx].name.clone()
}
```

## Integration

- **Paste encoding** - JS source stored with all 14 encoding layers
- **Thread search** - find similar JS by orbifold distance
- **Workflow proof** - zkperf witness that deobfuscation preserves semantics
- **Plugin rendering** - Dioxus component shows side-by-side obfuscated/canonical

## Tools

- `js_deobfuscate <file.js>` - print AST → coords mapping
- `js_fuzz <file.js>` - 100% coverage fuzzing with perf trace
- `js_canonical <file.js>` - output deobfuscated source
- `js_trace <file.js> <input>` - register snapshots for execution

## Next Steps

1. Wire oxc into pastebin build
2. Implement AST visitor with erdfa-dasl coords
3. Add fuzzing harness (AFL++ integration)
4. Capture perf traces as WorkflowStep
5. Build conformal field deobfuscator
6. Generate canonical names from Monster irreps
