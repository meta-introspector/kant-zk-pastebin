This project was edited by [Aristotle](https://aristotle.harmonic.fun).

To cite Aristotle:
- Tag @Aristotle-Harmonic on GitHub PRs/issues
- Add as co-author to commits:
```
Co-authored-by: Aristotle (Harmonic) <aristotle-harmonic@harmonic.fun>
```

# kant-zk-pastebin, ported to Lean 4

A machine-checked port of the [`meta-introspector/kant-zk-pastebin`](https://github.com/meta-introspector/kant-zk-pastebin)
pastebin (all branches surveyed) into Lean 4, together with a browser client
that implements the same algorithms and is checked against Lean-computed golden
vectors.

The Lean layer is the specification: every data format, address computation,
framing rule, stego embedding, sync rule and credit rule in the system is a Lean
definition, and the properties the original Rust code assumes informally are
stated and proved as theorems. The `web/` layer is an unverified JavaScript
transcription of exactly those definitions, so the running client and the proofs
talk about the same objects.

```
lake build                # builds every Lean module; 0 sorries, 0 warnings
lake exe emitwasm dist    # extracts dist/kant_kernel.wasm from Lean (no C toolchain needed)
node web/test.mjs         # 29 conformance checks of the JS layer against Lean golden vectors
node web/wasm-test.mjs    # validates and runs the extracted .wasm, and cross-checks it
python3 -m http.server -d web 8080   # then open http://localhost:8080/
```

## Rust → Lean module map

| upstream Rust | Lean module | what it covers |
|---|---|---|
| `src/dasl.rs` | `RequestProject/Kant/Dasl.lean` | `0xDA51` content IDs, nested/shard/harmonic-path CIDs, Monster-group primes, orbifold action, XOR merge algebra |
| `src/model.rs`, `src/paste.rs` | `RequestProject/Kant/Paste.lean` | paste records and the content-addressed store |
| `src/paste.rs` (rendering) | `RequestProject/Kant/Erdfa.lean` | eRDFa/HTML escaping |
| `src/storage.rs` | `RequestProject/Kant/Bytes.lean` | blobs, hex, FNV-1a digest, 64-hex-char witnesses |
| `src/sheaf.rs` | `RequestProject/Kant/Sheaf.lean` | DASL type / eigenspace / encoding taxonomy |
| `SNEAKERNET.md` | `RequestProject/Kant/Sneakernet.lean` | channel capacities, 5 MB social limit, chunking, framing, reassembly |
| `SNEAKERNET.md` (covert) | `RequestProject/Kant/Stego.lean` | LSB steganography in PNG/GIF/SVG carriers |
| `IPFS.md` | `RequestProject/Kant/Sync.lean` | IPFS / iroh / libp2p / torrent / archive.org / UUCP / QR-burst sync |
| new (credits) | `RequestProject/Kant/Credits.lean` | serve-to-earn credit ledger |
| new (code movies) | `RequestProject/Kant/CodeMovie.lean` | RLE snippets, Gödel numbering, circuits |
| — | `RequestProject/Kant/Pipeline.lean` | end-to-end paste → address → frame → stego → recover theorem |
| — | `RequestProject/Kant/Demo.lean` | `#guard`-checked worked examples of every layer |
| — | `RequestProject/Kant.lean` | aggregator |

## Theorem index

**Bytes / addressing**

- `Kant.Bytes.hexDecode_hexEncode` — hex encoding round-trips.
- `Kant.Bytes.digest_length`, `Kant.Bytes.witness_length` — digests are 32 bytes, witnesses 64 hex chars.
- `Kant.Dasl.decode_mkCid_of_lt`, `Kant.Dasl.mkCid_injective`, `Kant.Dasl.mkCid_lt` — the `0xDA51` bit layout is a faithful, injective, in-range encoding.
- `Kant.Dasl.monsterOrder_eq` — the product of the Monster prime powers is the Monster group order.
- `Kant.Dasl.rotate71_add/period/inverse` (and the `reflect59`, `dual47` analogues, plus the three commutation lemmas) — the orbifold symmetries form a commuting ℤ/71 × ℤ/59 × ℤ/47 action.
- `Kant.Dasl.mergeCids_comm/assoc/self/unit`, `Kant.Dasl.mergeAll_perm` — merging peer address sets is order-independent.

**Documents**

- `Kant.Erdfa.escape_unescape_id`, `escape_injective`, `escape_no_markup` — escaping is lossless and cannot emit markup.
- `Kant.Store.get_witness`, `get_put_eq`, `put_idem`, `get_put_of_ne`, `has_put_mono`, `put_comm_lookup` — the content-addressed store behaves like a map keyed by witness, and insertions commute.
- `Kant.Sheaf.daslType_roundTrip`, `fromName_name`, `prime_injective`, `section_card` — the sheaf taxonomy is a bijective labelling with 320 sections.

**Transport**

- `Kant.Sneakernet.chunk_flatten` — chunking loses nothing.
- `Kant.Sneakernet.chunk_length_le`, `frames_fit_social` — every frame fits the channel, and social exports stay under 5 MB.
- `Kant.Sneakernet.reassemble_frames`, `reassemble_perm`, `reassemble_frames_perm` — frames reassemble to the original payload regardless of arrival order.

**Covert channels**

- `Kant.Stego.extract_embed`, `extractBlob_embedBlob` — hidden payloads come back out exactly.
- `Kant.Stego.embed_preserves_high_bits`, `embed_lt_256` — embedding only touches the low bit, so the carrier stays a valid 8-bit sample.

**Network**

- `Kant.Sync.sync_preserves`, `sync_delivers`, `sync_idem`, `has_sync_iff` — sync adds exactly the remote pastes and nothing else, and is idempotent.
- `Kant.Sync.get_sync_iff`, `sync_converges` — collision-free peers converge to the same store no matter which side syncs first.

**Credits**

- `Kant.Credits.Ledger.serve_balance`, `serve_valid`, `totalEarned_serve` — serving bytes credits exactly the server.
- `Kant.Credits.Ledger.spend_eq_none_iff`, `spend_balance`, `spend_valid` — spending fails exactly when the balance is short, and never goes negative.
- `Kant.Credits.Ledger.earned_le_total`, `balance_le_totalEarned` — no credit is created out of nothing.

**Code movies**

- `Kant.CodeMovie.rleDecode_rleEncode`, `rleEncode_length` — compression round-trips.
- `Kant.CodeMovie.ungodel_godel`, `godel_injective`, `unmovie_movieGodel` — a whole movie is a single Gödel number you can recover it from.
- `Kant.CodeMovie.frameAt_periodic` — playback loops.
- `Kant.CodeMovie.Circuit.decodeCircuit_encodeCircuit`, `encode_injective` — circuits survive the same numeric encoding.

**End to end**

- `Kant.Pipeline.pipeline_roundTrip` — paste → witness → frames → LSB-stego carrier → recovered paste is the identity.
- `Kant.Pipeline.pipeline_witness` — the recovered paste has the witness it was addressed by.
- `Kant.Pipeline.publish_social_fits`, `carrier_capacity_needed` — published carriers respect the 5 MB limit and the stated capacity bound.

## Browser client (`web/`)

`web/kantzk.mjs` is a direct transcription of the Lean definitions (BigInt where
Lean uses `Nat`). `web/test.mjs` pins it to golden values computed by Lean —
run it with `node web/test.mjs`.

`web/index.html` is the client. It lets you

- paste text or fetch a URL, and address it by DASL CID + witness;
- pin it locally (Cache Storage via `web/sw.js`) so it gets a servable `/pin/<witness>` URL, and earn ledger credits when the service worker serves it;
- frame it for any channel and check the 5 MB social cap;
- hide a paste in a PNG via canvas LSB stego, or export SVG / animated-GIF-style frames;
- record a ≤ 5 MB WebM social export with `MediaRecorder`;
- read a paste aloud with `speechSynthesis` (TTS);
- play a code movie back through WebGL.

Everything in `web/` is *unverified*: it is checked only by `web/test.mjs`, not
by proof.

## WASM

`dist/kant_kernel.wasm` is a real WebAssembly binary extracted **from Lean
itself**: its bytes are computed by a verified encoder
(`RequestProject/Wasm/`), not by a C toolchain, so no emscripten or WASI SDK is
involved.

```
lake exe emitwasm dist    # writes dist/kant_kernel.wasm and dist/kernel-vectors.json
node web/wasm-test.mjs    # WebAssembly.validate + run + cross-check
```

Twenty-one `i64` functions are exported (hex digits, the FNV-1a digest round
and offset basis, big-endian byte expansion, DASL address arithmetic and the
merge algebra, serve credits, stego LSB write/read, the orbifold action, Cantor
pairing, the 5 MB social bound). For each one there is a theorem that the wasm code
computes the corresponding `Kant.*` definition, on top of a LEB128 round-trip
proof and a compiler-correctness theorem for the instruction fragment. The
design follows [`argumentcomputer/Wasm.lean`](https://github.com/argumentcomputer/Wasm.lean),
re-derived for the current toolchain and proved. See
[`docs/WASM-EXTRACTION.md`](docs/WASM-EXTRACTION.md).

The fragment has no linear memory or loops, so the list- and string-processing
definitions (`witness`, `frames`, `embedBlob`, `godel`, …) are not exported
directly; `web/kant-wasm.mjs` obtains `fnv1a`, `hexEncode`, `digest` and
`witness` by folding the verified per-step exports instead. `web/index.html`
loads the kernel on start-up and recomputes each paste's witness inside
WebAssembly, falling back to the JavaScript core if the binary is not served.

## Networking

See [`docs/WASM-AND-NETWORK.md`](docs/WASM-AND-NETWORK.md). Short version: the
Lean → C → WebAssembly path (an alternative to the extraction above, which
would cover the whole port) and the IPFS / iroh / libp2p / torrent /
archive.org integration are specified and scripted there, but **no running peer
service was produced in this repository**, and the emscripten toolchain that
path needs is not present in the build environment used here.
