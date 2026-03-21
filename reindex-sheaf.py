#!/usr/bin/env python3
"""Reindex Sheaf headers in-place using hash-derived fields (matches fixed sheaf.rs)."""
import hashlib, glob, sys

PRIMES = [2,3,5,7,11,13,17,19,23,29,31,41,47,59,71]
BOTT = ["R","C","H","H⊕H","H(2)","C(4)","R(8)","R(8)⊕R(8)"]
TYPES = {0:"MonsterWalk",1:"AstNode",2:"Protocol",3:"NestedCid",
         4:"HarmonicPath",5:"ShardId",6:"Eigenspace",7:"Hauptmodul"}
EIGEN = {range(0,12):"Earth", range(12,17):"Spoke", range(17,19):"Hub", range(19,20):"Clock"}

def eigenspace(b):
    v = b % 20
    if v < 12: return "Earth"
    if v < 17: return "Spoke"
    if v < 19: return "Hub"
    return "Clock"

def classify_type(content, hb):
    if b"```" in content or b"fn " in content or b"def " in content or b"pub " in content:
        return 1  # AstNode
    v = hb % 8
    if v == 0: return 0
    if v == 1: return 1
    if v == 2: return 2
    if v in (3,4,5): return 3
    if v == 6: return 6
    return 5

def compute_sheaf(content_bytes):
    h = hashlib.sha256(content_bytes).digest()
    # orbifold coords (matches dasl.rs orbifold_coords)
    l = int.from_bytes(h[0:4], 'little') % 71
    m = int.from_bytes(h[4:8], 'little') % 59
    n = int.from_bytes(h[8:12], 'little') % 47
    bott = h[12] % 8
    hecke = h[13] % 15
    eig = eigenspace(h[14])
    dtype = classify_type(content_bytes, h[15])
    hecke_prime = PRIMES[hecke]
    return f"{l},{m},{n} H/raw p=1 T{dtype} {eig} B{bott} T_{hecke_prime}"

updated = 0
for f in sorted(glob.glob("/mnt/data1/spool/uucp/pastebin/*.txt")):
    lines = open(f).readlines()
    sheaf_idx = None
    blank_idx = None
    for i, line in enumerate(lines):
        if line.startswith("Sheaf:"):
            sheaf_idx = i
        if blank_idx is None and line.strip() == "" and i > 0:
            blank_idx = i
    if sheaf_idx is None or blank_idx is None:
        continue
    content = "".join(lines[blank_idx+1:]).encode("utf-8")
    if not content.strip():
        continue
    new_sheaf = "Sheaf: " + compute_sheaf(content) + "\n"
    if lines[sheaf_idx] != new_sheaf:
        lines[sheaf_idx] = new_sheaf
        open(f, "w").write("".join(lines))
        updated += 1

print(f"Updated {updated} files")
