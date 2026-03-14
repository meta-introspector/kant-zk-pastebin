# SNEAKERNET — Self-Replicating Knowledge Network

A system where programs, proofs, and data travel as URLs, QR codes, WAV files,
and images. Each paste is a node. Combine nodes into new nodes. The network
grows. The pastebin replicates itself.

## Core Idea

```
content → IPFS CID → encode as URL/QR/WAV/morse → transmit → decode → verify CID → reconstruct
```

Every piece of data has a CID. CIDs compose. A program is a DAG of CIDs.
The pastebin itself is a DAG of CIDs. Transmit the root CID through any
channel — the receiver reconstructs everything from the network.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                  Static Pastebin                     │
│              (WASM, runs in browser)                 │
│                                                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐          │
│  │ RDFa/    │  │ IPFS     │  │ DASL     │          │
│  │ eRDFa    │  │ flatfs   │  │ Monster  │          │
│  │ triples  │  │ blocks   │  │ symmetry │          │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘          │
│       └──────────────┼─────────────┘                 │
│                      ▼                               │
│  ┌─────────────────────────────────────┐            │
│  │         Encoding Layer              │            │
│  │  URL · QR · WAV · Morse · Stego    │            │
│  └──────────────┬──────────────────────┘            │
│                 ▼                                    │
│  ┌─────────────────────────────────────┐            │
│  │         Transport Layer             │            │
│  │  Screen · Speaker · Camera · Mic   │            │
│  │  Clipboard · LocalStorage · File   │            │
│  └─────────────────────────────────────┘            │
└─────────────────────────────────────────────────────┘
```

## Phases

### Phase 1: URL Encoding (data: URIs + fragment CIDs)

Encode small pastes entirely in URLs. No server needed to read them.

```
data:text/html;base64,... (self-contained paste + viewer)
https://solana.solfunmeme.com/pastebin/paste/ID#ipfs:QmXYZ
```

- Paste content → IPFS block → base64 → data: URI
- Fragment identifier carries the CID for verification
- RDFa metadata embedded in the HTML
- Combine multiple URLs: each URL is a shard, reconstruct from k-of-n

### Phase 2: QR Code Transport

Encode CIDs and small payloads as QR codes.

- Single QR: CID reference (46 bytes for CIDv0)
- Multi-QR: chunked payload with sequence numbers + Reed-Solomon
- Animated QR: cycle through chunks on screen, camera captures
- RDFa triple per QR: subject/predicate/object as structured data

### Phase 3: Audio Transport (WAV/Modem/Morse)

Encode data as sound. BBS modem tones, morse code, FSK.

- Morse: CID as dots/dashes (human-decodable)
- FSK modem: ~300 baud, reliable over speaker/mic
- DTMF: hex digits as phone tones
- WAV file: embed data in audio, paste as attachment

### Phase 4: WASM Static Pastebin

The pastebin compiles to WASM and runs entirely in the browser.

- LocalStorage as block store (flatfs layout in IndexedDB)
- Service Worker for offline operation
- Import/export via all transport channels
- Self-replicating: the WASM binary is itself a paste with a CID

### Phase 5: Visual Transport

Screen capture, image steganography, video frames.

- Screenshot → OCR → extract QR/text/URLs
- Stego: hide data in PNG pixel LSBs (from eRDFa stego.rs)
- Video: encode data as frame sequence
- Screen recording: replay to reconstruct

### Phase 6: Network Composition

Combine pastes into programs. Programs into systems.

- DAG of CIDs = a program/proof
- Root CID = the entire system
- Merkle proof of inclusion for any node
- DASL orbifold coordinates for navigation
- RDFa triples link nodes semantically

## eRDFa Integration

From `~/02-february/22/dasl/rdfa-namespace/`:

| Module | Use in Sneakernet |
|--------|-------------------|
| `stego.rs` | Multi-channel steganographic encoding (16 strategies) |
| `crypto.rs` | Reed-Solomon error correction for lossy channels |
| `shards.rs` | k-of-n shard splitting (71 shards = Gandalf prime) |
| `symmetry.rs` | Monster group coordinate system |
| `erdfa-wasm` | Browser runtime for parsing/reconstructing |
| `acl.rs` | Access control for encrypted shards |

## Data Flow: Paste → URL → QR → WAV → Paste

```
1. Create paste         → content + CID + DASL + RDFa triples
2. Encode as URL        → data:text/html;base64,... (self-viewing)
3. URL → QR code        → scannable from any screen
4. QR → WAV             → modem tones carrying the QR data
5. WAV → decode         → reconstruct QR → URL → content
6. Verify CID           → SHA256 matches, content authentic
7. Store in new pastebin → the knowledge has traveled
```

## Self-Replication

The pastebin can replicate itself:

```
1. pastebin source code → series of IPFS blocks
2. blocks → CIDs → encoded as QR sequence
3. QR sequence displayed on screen
4. new device captures QR sequence
5. reconstructs source code from blocks
6. compiles via WASM (or nix)
7. new pastebin instance running
```

## URL Composition Algebra

URLs compose like functions:

```
paste(A) + paste(B) = paste(C)  where C.content = A ∘ B
CID(C) = ipfs_add(A.content + B.content)
DASL(C) = dasl_merge(DASL(A), DASL(B))  // XOR in orbifold space
```

A "program" is a paste whose content references other pastes by CID.
Execution = recursive CID resolution + WASM evaluation.

## File Format

Each paste carries RDFa metadata:

```html
<div vocab="https://dasl.dev/ns/" typeof="Paste">
  <meta property="ipfs:cid" content="QmXYZ..." />
  <meta property="dasl:address" content="0xda51..." />
  <meta property="dasl:orbifold" content="42,17,33" />
  <meta property="sneaker:encoding" content="url,qr,wav" />
  <meta property="sneaker:shards" content="71" />
  <meta property="sneaker:threshold" content="47" />
  <div property="content">...</div>
</div>
```
