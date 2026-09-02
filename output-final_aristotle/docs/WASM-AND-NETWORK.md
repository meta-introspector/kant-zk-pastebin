# WebAssembly extraction and the peer network

## Status, stated plainly

**Update.** A WebAssembly binary *is* now produced in this repository, by a
different route than the one described in section 1 below: `lake exe emitwasm
dist` writes `dist/kant_kernel.wasm`, whose bytes are computed by a verified
Lean encoder rather than by a C toolchain. It covers the arithmetic kernel, not
the whole port. See `docs/WASM-EXTRACTION.md`.

The rest of this section, and section 1, describe the *other* route — Lean → C
→ emscripten, which would cover the list- and string-processing definitions
too. That route is still unbuilt here, and the caveats below still apply to it.

**No emscripten-built `.wasm` binary was produced in this repository, and no
peer service was started or deployed.** The build environment used to produce
this port has no emscripten (`emcc`), no WASI SDK, no `clang`/`wasm-ld`, and no
outbound peer networking. What exists here is:

- a complete, machine-checked Lean 4 specification of the whole system
  (`RequestProject/Kant/`, `lake build`, no `sorry`);
- a browser client that implements the same algorithms in JavaScript and is
  checked against Lean-computed golden vectors (`web/`, `node web/test.mjs`);
- a verified Lean → wasm encoder and the binary it emits (`RequestProject/Wasm/`,
  `dist/kant_kernel.wasm`, `node web/wasm-test.mjs`);
- the build recipe and network design below, which is what you would run on a
  machine that does have the toolchain.

Everything below marked *design* is unimplemented and unverified. Do not read it
as a description of running code.

## 1. Lean → WebAssembly (design + recipe)

Lean 4 compiles through C, so the extraction path is:

```
Kant/*.lean  --lake build--> .olean + .c  --emcc--> kantzk.wasm + kantzk.js
```

`scripts/build-wasm.sh` in this repository automates that, and refuses to run
(with an explanatory message) when the toolchain is absent, which is the case
here.

The three practical constraints:

1. **Runtime.** The generated C links against `libleanrt` and a GC. Both build
   for `wasm32-emscripten`; the Lean 4 source tree ships an emscripten
   cross-build (`stage1` with `-DCMAKE_TOOLCHAIN_FILE=Emscripten.cmake`), and
   you need that runtime built for the same toolchain version as the compiler
   that emitted the C.
2. **Entry points.** Only the functions you export are reachable from JS. The
   intended surface is exactly the pure core: `witness`, `nestedCid`,
   `daslHex`, `orbifoldCoords`, `escape`, `frames`, `reassemble`, `embedBlob`,
   `extractBlob`, `godel`/`ungodel`, `circuitEncode`/`circuitDecode`. Each takes
   and returns byte arrays, so the JS boundary is `malloc` + copy + call + copy
   back, with no Lean objects escaping.
3. **Mathlib.** The proofs import Mathlib, but none of the *computable*
   definitions do at runtime. Extracting a Mathlib-free compute-only subset
   (a `KantCore` library with the definitions and no theorems) keeps the wasm
   binary small; this repository keeps definitions and proofs together for
   readability, so splitting is the first step of a real wasm build.

Until that binary exists, `web/kantzk.mjs` plays its role for the definitions the
extracted kernel does not cover: it is a *manual*
transcription of the same definitions, and `web/test.mjs` pins it to values
computed by Lean, so a divergence between the two shows up as a test failure
rather than silently.

### Golden vectors

The conformance vectors in `web/test.mjs` were computed by the Lean side (see
`RequestProject/Kant/Demo.lean`, whose `#guard`s are checked at build time).
Examples:

| quantity | value |
|---|---|
| `witness "hello"` | `ff810f291f187b808a0183f83c0466874573ef5c4c6d7d9ed430c6f7d710f605` |
| `daslHex (nestedCid "hello")` | `0xda5132a0b0f291f1` |
| `orbifoldCoords "hello"` | `(60, 29, 5)` |
| `godel [1,2,3]` | `29586` |
| `movieGodel demoMovie` | `644468914277383917536159541511687883` |

Any wasm build must reproduce these; they are the contract between the proved
Lean core and any other implementation.

## 2. Content addressing is the network protocol

The reason the network layer is small is that addressing does the work. A paste
is named by `Kant.Bytes.witness` (64 hex chars) and by a `0xDA51` CID
(`Kant.Dasl.nestedCid`). Both are pure functions of the bytes, so:

- `Kant.Store.get_witness` — a store lookup returns a paste with that witness;
- `Kant.Store.put_idem` — re-adding a paste you already have is a no-op;
- `Kant.Store.put_comm_lookup` — the order two pastes arrive in does not matter;
- `Kant.Sync.sync_preserves` / `sync_delivers` — a sync adds exactly the remote
  pastes and invents nothing;
- `Kant.Sync.sync_converges` — two collision-free peers that sync each other end
  up with the same store regardless of who goes first.

That last theorem is the whole justification for treating IPFS, iroh, libp2p,
BitTorrent, archive.org, UUCP and a burst of QR codes as *interchangeable*
transports: `Kant.Sync.Source` is an enumeration, and `sync` does not branch on
it. A transport is correct for this system exactly when it delivers the bytes of
a paste intact; the proofs then apply unchanged.

## 3. Transport bindings (design)

| `Kant.Sync.Source` | binding | address derivation |
|---|---|---|
| `ipfs` | `js-ipfs` / Kubo HTTP API, or `helia` in-browser | CID from `nestedCid`, block put/get; pin = local pin |
| `iroh` | `iroh` blobs over QUIC, node ticket in the paste header | blob hash ties to `witness` |
| `libp2p` | `js-libp2p` with gossipsub topic `kantzk/<daslHex>` + bitswap | topic from `daslHex` |
| `torrent` | `webtorrent` in-browser; one paste per torrent, or a pack per shard | infohash recorded alongside the witness |
| `archiveOrg` | fetch item metadata, then `<item>_archive.torrent`, seed via `webtorrent` | archive identifier stored as an alias for the witness |
| `uucp` | file drop into a spool dir; frames from `Kant.Sneakernet.frames` | filename `= seq` |
| `qrBurst` | animated QR of `Kant.Sneakernet.frames`, camera decode | frame `seq` in the QR payload |
| `localDisk` | Cache Storage / OPFS (`web/sw.js`) | `/pin/<witness>` |

The archive.org direction is the interesting one and it is deliberately
one-directional in the design: archive.org items are fetched, converted into
pastes (bytes → witness → store), and then reseeded to the other transports.
Nothing is pushed to archive.org.

**Framing.** Every transport that has a size limit reuses the same framing:
`Kant.Sneakernet.chunk` splits the payload, `frames` numbers the pieces, and
`reassemble` puts them back. `chunk_flatten` says nothing is lost,
`chunk_length_le` says no frame exceeds the channel capacity,
`frames_fit_social` says a social-media export stays under 5 MB, and
`reassemble_frames_perm` says arrival order does not matter — which is what
makes a swarm, a torrent, and a stack of QR codes all acceptable carriers.

## 4. Pinning and credits

A pinned paste in the browser is a Cache Storage entry served by `web/sw.js` at
`/pin/<witness>`. When the worker serves one it posts `{kind:"served"}` back to
the page, which credits the operator through `Kant.Credits.Ledger.serve`.

The ledger is where the "earn credits when you serve" requirement becomes a
theorem rather than a promise:

- `serve_balance` — serving credits exactly the serving peer, by
  `creditsFor` (one credit per KiB, `creditsFor_kib`);
- `totalEarned_serve` — the total credit in the system rises by exactly that;
- `spend_eq_none_iff` — a spend fails exactly when the balance is insufficient,
  so a balance can never go negative;
- `earned_le_total` and `balance_le_totalEarned` — no peer can hold more than
  was ever minted.

This is a local, unsigned ledger: it is *arithmetically* sound, not
Byzantine-fault-tolerant. Making it trustworthy between mutually distrusting
peers needs signed serve receipts and a consensus or accumulator layer, neither
of which is specified here. The zero-knowledge component named in the upstream
project ("zk") is likewise out of scope for this port: the witness/commitment
plumbing (`Kant.Bytes.witness`, `Kant.Store.get_witness`) is proved, the proof
system is not.

## 5. Covert and social export paths

`Kant.Stego` is the shared substrate for every "share your status in a picture"
requirement:

- `embedBlob` writes payload bits into the low bit of carrier samples;
- `extractBlob_embedBlob` — the payload comes back exactly;
- `embed_preserves_high_bits` and `embed_lt_256` — the carrier's visible high
  bits are untouched and samples stay in range, which is what makes the result
  a valid image rather than noise;
- `capacityBytes` / `fits_iff_capacity` — how big a carrier you need.

In the client this drives PNG (canvas `ImageData`), SVG (payload in per-glyph
coordinates), animated-frame export, and the ≤ 5 MB WebM social export, whose
size bound is `Kant.Sneakernet.frames_fit_social`. `Kant.Pipeline.pipeline_roundTrip`
chains the whole thing: paste → witness → frames → stego carrier → recovered
paste is the identity, and `pipeline_witness` says the recovered paste still
answers to the address it was published under.

## 6. Code movies

`Kant.CodeMovie` gives playback its formats: RLE for the snippets
(`rleDecode_rleEncode`), a Gödel number per frame and per movie
(`unmovie_movieGodel`, so an entire "demo" is one integer you can post as text),
looping playback (`frameAt_periodic`), and a circuit language with the same
numeric encoding (`Circuit.decodeCircuit_encodeCircuit`). The WebGL player in
`web/index.html` consumes exactly these.
