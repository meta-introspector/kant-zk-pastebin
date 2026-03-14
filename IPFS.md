# IPFS Integration — Pure Rust, No Daemon

kant-pastebin computes IPFS content identifiers and writes blocks directly
to the local go-ipfs/kubo block store. No daemon process, no HTTP API, no
CLI shelling — just filesystem writes.

## Architecture

```
content bytes
      │
      ▼
┌─────────────┐
│  FileAdder  │  rust-unixfs crate (git submodule: vendor/rust-ipfs)
│  (UnixFS    │  Encodes content as dag-pb protobuf blocks.
│   dag-pb)   │  Chunks large files into a balanced Merkle DAG.
└──────┬──────┘
       │ yields (CID, block_bytes) pairs
       ▼
┌─────────────┐
│ write_block │  Writes each block to go-ipfs flatfs:
│  (flatfs)   │    ~/.ipfs/blocks/{shard}/{key}.data
└──────┬──────┘
       │ returns root CID
       ▼
┌─────────────┐
│ paste header│  Stored as IPFS: QmcFFn... in paste file
│  + JSON API │  Returned as ipfs_cid in POST /paste response
└─────────────┘
```

## Flatfs Layout

go-ipfs stores blocks in a sharded directory tree under `~/.ipfs/blocks/`.
The sharding scheme is **next-to-last/2**:

```
key   = BASE32_NOPAD_UPPER(multihash)
shard = key[len-3 .. len-1]   (2nd-to-last two characters)
path  = ~/.ipfs/blocks/{shard}/{key}.data
```

Example for `QmcFFnmxaUcMiF7ePCtqndf7rfZzsG6jrW46gDM7ToD2q9`:

```
multihash = 1220... (0x12=sha256, 0x20=32 bytes, then digest)
key       = CIQO...XY
shard     = last-2-before-last char of key
path      = ~/.ipfs/blocks/XY/CIQO...XY.data
```

## CID Versions

- **CIDv0** (`Qm...`): Returned by `FileAdder` (base58btc, dag-pb + sha256).
  This is what `ipfs add` produces by default.
- **CIDv1** (`bafy...`): Available via `cid_to_v1()` for display.
  Same content, different encoding.

Both versions resolve to the same multihash and the same flatfs block path.

## Data Flow on Paste Creation

```
POST /paste {"content": "hello"}
  → handlers::create_paste()
    → ipfs::ipfs_add("hello")
      → FileAdder::push(b"hello")
      → FileAdder::finish()
        → yields (Qm..., <dag-pb block bytes>)
      → write_block() → ~/.ipfs/blocks/XX/KEY.data
    → dasl::dasl_cid(b"hello")  → 0xda51...
    → write paste file with IPFS: and DASL: headers
  ← {"ipfs_cid": "Qm...", ...}
```

## Verification

```sh
# Create a paste
curl -s -X POST http://127.0.0.1:8090/paste \
  -H 'Content-Type: application/json' \
  -d '{"content":"test"}' | jq .ipfs_cid

# Read it back via ipfs (no daemon needed, reads flatfs directly)
ipfs cat QmcFFnmxaUcMiF7ePCtqndf7rfZzsG6jrW46gDM7ToD2q9
```

## ContentStore Backends

| Backend        | How it works                              | Use case          |
|----------------|-------------------------------------------|-------------------|
| `RustStore`    | `rust-unixfs` FileAdder + flatfs write    | Default, WASM-ok  |
| `DaslCborStore`| CBOR envelope → then RustStore            | Monster symmetry  |
| `IpfsCliStore` | Shells out to `ipfs add`                  | Fallback          |

## DASL/CBOR Envelope

`wrap_dasl_cbor()` creates a CBOR object containing:

| Field       | Description                                    |
|-------------|------------------------------------------------|
| `prefix`    | `0xDA51` marker                                |
| `dasl_type` | 3 (nested CID)                                 |
| `orbifold`  | (l mod 71, m mod 59, n mod 47) coordinates     |
| `bott`      | Bott periodicity index (0–7)                   |
| `data`      | Raw content bytes                              |
| `cid`       | IPFS CID string                                |
| `dasl`      | 64-bit DASL Monster symmetry address           |

## Dependencies

- `rust-unixfs` — UnixFS dag-pb encoding (git submodule at `vendor/rust-ipfs`)
- `ipld-core` — CID type
- `data-encoding` — base32 encoding for flatfs keys
- `dirs-next` — home directory resolution
- `sha2` — SHA-256 for local CID and DASL
- `ciborium` — CBOR serialization for DASL envelopes

## Repo Path Resolution

1. `$IPFS_PATH` environment variable (if set)
2. `~/.ipfs` (default)
3. If neither exists, blocks are not written (CID still computed)
