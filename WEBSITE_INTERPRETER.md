# Website Interpreter & Fuzzer

## Architecture

```
HTML + CSS + JS → Rust AST → Monster Orbifold → Conformal Field → WASM
```

## Components

### 1. Ingest Pipeline
```rust
struct WebsiteArtifact {
    html_dom: RcDom,                      // html5ever parsed
    css_rules: Vec<CssRule>,              // cssparser parsed
    js_asts: Vec<Program>,                // oxc parsed
    orbifold_coords: Vec<OrbifoldCoords>, // all nodes → coords
    ipfs_cids: HashMap<String, Cid>,     // static assets
}
```

### 2. Static Evaluation
- Parse all HTML/CSS/JS from `/mnt/data1/kant/pastebin/static/`
- Extract DOM structure → orbifold coords
- Map CSS selectors → conformal arrows
- Compile JS to Rust via oxc AST transformation

### 3. Dynamic Evaluation
- Simulate browser runtime in Rust
- Execute JS via interpreted AST walk
- Track register state at each orbifold coord
- Capture side effects as workflow steps

### 4. IPFS Simulation
- Local filesystem mirror at `/var/spool/ipfs/`
- CID → file mapping via erdfa-plugin-ipfs
- Replay all IPFS operations from nginx logs

### 5. Chat Replay
- Parse chat transcripts from `/var/log/pastebin/`
- Each message → paste with orbifold coords
- Thread structure = conformal arrows
- Model conversation as field evolution

### 6. Nginx Log Ingestion
```rust
struct NginxLogEntry {
    timestamp: u64,
    method: String,
    path: String,
    status: u16,
    coords: OrbifoldCoords,  // hash(path) → coords
}
```

### 7. Fuzzing
- AFL++ on compiled Rust website
- Mutate inputs guided by orbifold distance
- 100% path coverage via conformal geodesics
- Perf trace every execution path

### 8. WASM Generation
```rust
// JS → Rust → WASM
fn js_to_wasm(js: &str) -> Vec<u8> {
    let ast = parse_js(js);
    let rust_code = ast_to_rust(&ast);
    compile_to_wasm(&rust_code)
}
```

## Implementation

### Phase 1: Ingest Kant Pastebin
```bash
website_ingest /mnt/data1/kant/pastebin/static/
  → parses all HTML/CSS/JS
  → outputs WebsiteArtifact CBOR
  → stores in paste with encoding=Document
```

### Phase 2: Compile to Rust
```bash
website_compile artifact.cbor
  → generates src/generated/website.rs
  → implements ZosPlugin trait
  → exports run() function
```

### Phase 3: Fuzz
```bash
website_fuzz src/generated/website.rs
  → AFL++ with orbifold-guided mutations
  → captures all execution paths
  → outputs perf traces as Workflow
```

### Phase 4: Generate WASM
```bash
website_wasm src/generated/website.rs
  → compiles to .wasm
  → optimizes via circuit optimizer
  → outputs with source maps
```

### Phase 5: Replay Logs
```bash
nginx_replay /var/log/nginx/access.log
  → parses each request
  → executes against compiled website
  → captures orbifold coords per request
  → models traffic as conformal field
```

### Phase 6: Chat Ingestion
```bash
chat_ingest /var/log/pastebin/chats/
  → parses transcripts
  → creates Thread per conversation
  → links messages via ConformalArrow
  → stores in pastebin
```

## Files

- `src/bin/website_ingest.rs` - parse HTML/CSS/JS → artifact
- `src/bin/website_compile.rs` - artifact → Rust code
- `src/bin/website_fuzz.rs` - AFL++ fuzzing harness
- `src/bin/website_wasm.rs` - Rust → WASM compiler
- `src/bin/nginx_replay.rs` - log parser + executor
- `src/bin/chat_ingest.rs` - chat transcript → threads

## Data Flow

```
Static files → Ingest → Artifact (CBOR)
                ↓
            Compile → Rust code
                ↓
            Fuzz → Perf traces
                ↓
            WASM → Optimized binary
                ↓
        Nginx logs → Request replay → Field model
                ↓
        Chat logs → Thread structure → Conformal arrows
```

## Output

All artifacts stored as pastes with full encoding stack:
- Bit: raw bytes
- Token: lexer output
- Statement: AST nodes
- Function: compiled Rust
- Module: website.rs
- Package: WASM binary
- URL: IPFS CID
- RDFa: semantic graph
- CBOR: serialized artifact
- Ontology: Monster type system
