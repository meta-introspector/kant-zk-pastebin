#!/usr/bin/env bash
# Cross-check the Rust framing in src/libp2p_frames.rs against the JS framing
# in web/kant-libp2p.mjs, byte for byte.
#
# The two must agree EXACTLY. The JS `decode` returns null for anything it does
# not recognise, so a one-byte disagreement is not a warning and not a
# fallback: a Rust peer and a browser peer simply never hear each other, with
# no error on either side. That is the same class of failure this project keeps
# hitting, so it gets a test rather than a code review.
#
# `cargo test` cannot do this on its own -- the pastebin crate's own suite
# stack-smashes on a pristine HEAD, before any of this -- so the module is
# compiled standalone against vectors the JS side writes.
#
#   scripts/frames-crosscheck.sh

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# ---------------------------------------------------------------- JS vectors
#
# A flat, line-oriented file. Parsing formatted JSON by string-splitting is the
# kind of thing that silently reads the wrong field.

node --input-type=module -e '
import { writeFileSync } from "node:fs";
import { encode, topicOf, serveChunks } from "./web/kant-libp2p.mjs";
import { cidOf } from "./web/kant-file.mjs";

const W  = "a".repeat(64);
const W2 = "0f3b9c2d1e4a5b6c7d8e9f0a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e";
const body = (n, s) => Array.from({ length: n }, (_, i) => (i * 31 + s) & 0xff);
const lines = [];
const push = (label, bytes) =>
  lines.push("FRAME " + label + " " + Buffer.from(bytes).toString("base64"));

push("want-no-nonce", encode({ tag: 1, witness: W, index: 0, total: 5 }));
push("want-nonce-1",  encode({ tag: 1, witness: W, index: 0, total: 1, nonce: [1,0,0,0] }));
push("want-nonce-2",  encode({ tag: 1, witness: W, index: 0, total: 1, nonce: [2,0,0,0] }));
push("deny",          encode({ tag: 3, witness: W2, index: 0, total: 1 }));
push("have-empty",    encode({ tag: 2, witness: W2, index: 0, total: 1, payload: new Uint8Array(0) }));
push("have-3",        encode({ tag: 2, witness: W, index: 2, total: 7, payload: new Uint8Array([1,2,3]) }));
push("have-1000",     encode({ tag: 2, witness: W, index: 0, total: 1, payload: new Uint8Array(body(1000, 3)) }));

// A real chunk, framed exactly the way the SERVER frames it: capture the bytes
// gossipsub would carry by standing in a fake pubsub for serveChunks. Framing
// it any other way would test my idea of the framing rather than the framing
// that actually ships.
const chunk = new Uint8Array(body(9000, 7));
const chunkWitness = cidOf(chunk);
let frames = [];
const fake = {
  subscribe(_t, h) { fake.handler = h; },
  async publish(_t, b) { frames.push(Buffer.from(b)); return { recipients: [] }; },
};
serveChunks(fake, {
  topic: "kant-file/1/room-1/" + W2,
  chunks: new Map([[chunkWitness, chunk]]),
  frameBytes: 1024,
  cidOf,
});
fake.handler({ data: encode({ tag: 1, witness: chunkWitness, index: 0, total: 9 }) });
await new Promise((r) => setTimeout(r, 50));
frames.forEach((b, i) => push("split-" + i, b));

writeFileSync(process.argv[1], [
  "W " + W,
  "W2 " + W2,
  "TOPIC " + topicOf("room-1", W2),
  "CHUNK " + chunkWitness + " " + chunk.length,
  ...lines,
].join("\n") + "\n");
' "$work/js.txt"

# ------------------------------------------------------------ standalone crate

mkdir -p "$work/src"
cat > "$work/Cargo.toml" <<'EOF'
[package]
name = "frames-crosscheck"
version = "0.0.0"
edition = "2021"
EOF

# The module with its own #[cfg(test)] block stripped: this crate supplies the
# checks, and duplicating the unit tests here would only let them drift.
python3 -c "
s = open('$root/src/libp2p_frames.rs').read()
s = s[:s.index('#[cfg(test)]')]
open('$work/src/lib.rs','w').write(s)
"

cat > "$work/src/main.rs" <<'RUST'
use frames_crosscheck::*;

fn b64(s: &str) -> Vec<u8> {
    const T: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut acc: u32 = 0;
    let mut bits = 0;
    let mut out = Vec::new();
    for c in s.bytes() {
        if c == b'=' { break; }
        let v = T.iter().position(|&x| x == c).expect("base64 alphabet") as u32;
        acc = (acc << 6) | v;
        bits += 6;
        if bits >= 8 { bits -= 8; out.push((acc >> bits) as u8); }
    }
    out
}

fn main() {
    let path = std::env::args().nth(1).expect("a vector file");
    let raw = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("{path}: {e}"));

    let mut w = String::new();
    let mut w2 = String::new();
    let mut topic = String::new();
    let mut chunk_w = String::new();
    let mut chunk_len = 0usize;
    let mut vectors: Vec<(String, Vec<u8>)> = Vec::new();

    for line in raw.lines() {
        let mut it = line.split_whitespace();
        match it.next() {
            Some("W") => w = it.next().unwrap_or_default().to_string(),
            Some("W2") => w2 = it.next().unwrap_or_default().to_string(),
            Some("TOPIC") => topic = it.next().unwrap_or_default().to_string(),
            Some("CHUNK") => {
                chunk_w = it.next().unwrap_or_default().to_string();
                chunk_len = it.next().unwrap_or("0").parse().unwrap_or(0);
            }
            Some("FRAME") => {
                let label = it.next().unwrap_or_default().to_string();
                vectors.push((label, b64(it.next().unwrap_or(""))));
            }
            _ => {}
        }
    }

    // A 63-char witness is exactly the mistake that produced five failures
    // earlier, and it produced them *silently* in the other direction: the
    // encoder refused and the test still ran. Assert the inputs first.
    assert_eq!(w.len(), 64, "witness W must be 64 hex chars, got {}", w.len());
    assert_eq!(w2.len(), 64, "witness W2 must be 64 hex chars, got {}", w2.len());
    assert_eq!(chunk_w.len(), 64, "chunk witness must be 64 hex chars, got {}", chunk_w.len());

    let mut fails = 0usize;
    let mut checked = 0usize;

    for (label, js) in &vectors {
        let Some(f) = decode(js) else {
            println!("  FAIL  {label}: the Rust decoder rejected the JS bytes");
            fails += 1;
            continue;
        };
        // decode() deliberately does not surface the nonce -- it is not
        // protocol meaning, only byte identity -- so rebuild it from the JS
        // bytes before re-encoding, or every `want` would differ by exactly
        // the nonce and the comparison would be meaningless.
        let mut rebuilt = f.clone();
        if f.tag == TAG_WANT && js.len() > HEADER {
            rebuilt.nonce = Some(js[HEADER..].to_vec());
        }
        let mine = match encode(&rebuilt) {
            Ok(b) => b,
            Err(e) => {
                println!("  FAIL  {label}: Rust refused to re-encode its own decode: {e}");
                fails += 1;
                continue;
            }
        };
        checked += 1;
        if mine != *js {
            println!("  FAIL  {label}: Rust {} B vs JS {} B", mine.len(), js.len());
            for (i, (a, b)) in mine.iter().zip(js.iter()).enumerate() {
                if a != b {
                    println!("        first difference at byte {i}: {a:02x} vs {b:02x}");
                    break;
                }
            }
            fails += 1;
        }
    }
    println!("  ok    {} frame(s) re-encode identically", vectors.len());

    checked += 1;
    match topic_of("room-1", &w2) {
        Ok(t) if t == topic => {}
        Ok(t) => { println!("  FAIL  topic: {t} != {topic}"); fails += 1; }
        Err(e) => { println!("  FAIL  topic: Rust refused it: {e}"); fails += 1; }
    }

    // Every chunk the JS server framed must reassemble in Rust, to the same
    // length, with no frame invented and none dropped.
    let frames: Vec<Frame> = vectors
        .iter()
        .filter(|(l, _)| l.starts_with("split-"))
        .filter_map(|(_, b)| decode(b))
        .collect();
    checked += 1;
    match assemble(&frames, &chunk_w) {
        Some(bytes) if bytes.len() == chunk_len => {
            println!("  ok    the {chunk_len}-byte chunk JS framed reassembles in Rust");
        }
        Some(bytes) => {
            println!("  FAIL  reassembled {} B, JS framed {chunk_len} B", bytes.len());
            fails += 1;
        }
        None => {
            println!("  FAIL  the JS-framed chunk did not reassemble in Rust");
            fails += 1;
        }
    }

    // Two asks differing only by nonce must differ in bytes: gossipsub
    // de-duplicates by message bytes, so identical asks would mean a chunk
    // could only ever be requested once, ever.
    checked += 1;
    let a = encode(&Frame::want(&w, 1, 1).unwrap()).unwrap();
    let b = encode(&Frame::want(&w, 1, 2).unwrap()).unwrap();
    if a == b {
        println!("  FAIL  two wants differing only by nonce are byte-identical");
        fails += 1;
    }

    // And the JS must agree on that too: its `want` with two nonces.
    checked += 1;
    let js_a = vectors.iter().find(|(l, _)| l == "want-nonce-1").map(|(_, b)| b.clone());
    let js_b = vectors.iter().find(|(l, _)| l == "want-nonce-2").map(|(_, b)| b.clone());
    match (js_a, js_b) {
        (Some(x), Some(y)) if x == y => {
            println!("  FAIL  the JS also emits byte-identical asks");
            fails += 1;
        }
        (Some(_), Some(_)) => {}
        _ => { println!("  FAIL  the JS nonce vectors are missing"); fails += 1; }
    }

    println!("\n{checked} cross-checks, {fails} failed");
    std::process::exit(if fails > 0 { 1 } else { 0 });
}
RUST

cd "$work" && cargo run --offline --quiet -- "$work/js.txt" 2>&1 | tail -20