/-
# The Kant kernel as a WebAssembly module

The pastebin's hot paths — hex digits, DASL address arithmetic, the merge
algebra, serve credits, stego least-significant-bit writes, the orbifold
action and the 5 MB social-export bound — are pure 64-bit integer
functions.  This module expresses each of them in the verified wasm
fragment of `RequestProject.Wasm.Syntax`, so that
`RequestProject.Wasm.Encode.module` can emit them as an actual `.wasm`
binary.

`RequestProject.Wasm.KernelSpec` proves that each of these expressions
evaluates, under the wasm semantics, to the value of the corresponding
Lean definition in `RequestProject.Kant.*`.

This file is Mathlib-free: it is the compute-only core that is extracted.
-/
import RequestProject.Wasm.Syntax
import RequestProject.Wasm.Encode

namespace Kant.Wasm.Kernel

open Kant.Wasm
open Kant.Wasm.Expr

/-! ## Constants shared with the Lean development -/

/-- `0xDA51`, the DASL magic prefix. -/
def daslPrefix : Nat := 0xDA51

/-- `5 * 1024 * 1024`, the social-export size limit in bytes. -/
def socialLimit : Nat := 5 * 1024 * 1024

/-! ## The kernel functions

Each is an `Expr` over the function's parameters (`Expr.var 0`, `…`). -/

/-- The ASCII code of the lowercase hex digit of `e`, for `e < 16`.
Branch-free: `48 + e + 39·[e ≥ 10]`. -/
def hexDigitOf (e : Expr) : Expr :=
  add (add (const 48) e) (mul (const 39) (cmp .geu e (const 10)))

/-- `hex_digit(n)` — the ASCII code of the lowercase hex digit of `n < 16`. -/
def hexDigitE : Expr := hexDigitOf (var 0)

/-- `hex_hi(b)` — the first hex digit of a byte. -/
def hexHiE : Expr := hexDigitOf (divC (var 0) 16)

/-- `hex_lo(b)` — the second hex digit of a byte. -/
def hexLoE : Expr := hexDigitOf (modC (var 0) 16)

/-- `cid_prefix(c)` — the top 16 bits of a DASL content id. -/
def cidPrefixE : Expr := divC (var 0) (2 ^ 48)

/-- `cid_type(c)` — the 4-bit type field. -/
def cidTypeE : Expr := modC (divC (var 0) (2 ^ 44)) 16

/-- `cid_payload(c)` — the low 44 bits. -/
def cidPayloadE : Expr := modC (var 0) (2 ^ 44)

/-- `mk_cid(typ, payload)` — assemble a DASL content id. -/
def mkCidE : Expr :=
  add (add (mul (const daslPrefix) (const (2 ^ 48))) (mul (var 0) (const (2 ^ 44)))) (var 1)

/-- `merge_cids(a, b)` — XOR the low 48 bits, keep the `0xDA51` prefix. -/
def mergeCidsE : Expr :=
  add (mul (const daslPrefix) (const (2 ^ 48)))
    (xor (modC (var 0) (2 ^ 48)) (modC (var 1) (2 ^ 48)))

/-- `credits_for(bytes)` — one credit per kilobyte served. -/
def creditsForE : Expr := divC (var 0) 1024

/-- `capacity_bytes(samples)` — stego payload capacity of a carrier. -/
def capacityBytesE : Expr := divC (var 0) 8

/-- `social_chunks(len)` — number of 5 MB pieces a payload is split into. -/
def socialChunksE : Expr := divC (add (var 0) (const (socialLimit - 1))) socialLimit

/-- `fits_social(len)` — `1` when a payload fits one social export. -/
def fitsSocialE : Expr := cmp .leu (var 0) (const socialLimit)

/-- `lsb_embed(sample, bit)` — overwrite the least significant bit. -/
def lsbEmbedE : Expr :=
  add (mul (const 2) (divC (var 0) 2)) (modC (var 1) 2)

/-- `lsb_extract(sample)` — read the least significant bit back. -/
def lsbExtractE : Expr := modC (var 0) 2

/-- The FNV-1a 64-bit prime. -/
def fnvPrimeConst : Nat := 1099511628211

/-- `fnv_offset()` — the FNV-1a 64-bit offset basis, `14695981039346656037`.
It exceeds `2 ^ 63`, which a single `i64.const` cannot hold as a
non-negative literal, so it is assembled from two smaller constants. -/
def fnvOffsetE : Expr := add (mul (const 2) (const 7347990519673328018)) (const 1)

/-- `fnv1a_step(h, b)` — one FNV-1a round. -/
def fnvStepE : Expr := mul (Expr.xor (var 0) (var 1)) (const fnvPrimeConst)

/-- `u64_byte(x, i)` — byte `i` of the big-endian expansion of `x`. -/
def u64ByteE : Expr :=
  andE (Expr.bin .shru (var 0) (mul (const 8) (sub (const 7) (var 1)))) (const 255)

/-- `cantor_pair(a, b)` — the Cantor pairing `Nat.pair`, branch-free:
`[a < b]·(b² + a) + [a ≥ b]·(a² + a + b)`, exactly one indicator being `1`. -/
def cantorPairE : Expr :=
  add
    (mul (cmp .ltu (var 0) (var 1)) (add (mul (var 1) (var 1)) (var 0)))
    (mul (cmp .geu (var 0) (var 1)) (add (add (mul (var 0) (var 0)) (var 0)) (var 1)))

/-- `rotate71(l, k)` — the order-71 rotation of the orbifold action. -/
def rotate71E : Expr := modC (add (var 0) (var 1)) 71

/-- `reflect59(m, k)` — the order-59 reflection. -/
def reflect59E : Expr := modC (add (var 0) (var 1)) 59

/-- `dual47(n, k)` — the order-47 duality. -/
def dual47E : Expr := modC (add (var 0) (var 1)) 47

/-! ## The module -/

/-- The exported Kant kernel: twenty-one `i64` functions. -/
def kernelModule : Module :=
  { funcs :=
      [ { name := "hex_digit", arity := 1, body := hexDigitE },
        { name := "cid_prefix", arity := 1, body := cidPrefixE },
        { name := "cid_type", arity := 1, body := cidTypeE },
        { name := "cid_payload", arity := 1, body := cidPayloadE },
        { name := "mk_cid", arity := 2, body := mkCidE },
        { name := "merge_cids", arity := 2, body := mergeCidsE },
        { name := "credits_for", arity := 1, body := creditsForE },
        { name := "capacity_bytes", arity := 1, body := capacityBytesE },
        { name := "social_chunks", arity := 1, body := socialChunksE },
        { name := "fits_social", arity := 1, body := fitsSocialE },
        { name := "lsb_embed", arity := 2, body := lsbEmbedE },
        { name := "lsb_extract", arity := 1, body := lsbExtractE },
        { name := "hex_hi", arity := 1, body := hexHiE },
        { name := "hex_lo", arity := 1, body := hexLoE },
        { name := "fnv_offset", arity := 0, body := fnvOffsetE },
        { name := "fnv1a_step", arity := 2, body := fnvStepE },
        { name := "u64_byte", arity := 2, body := u64ByteE },
        { name := "cantor_pair", arity := 2, body := cantorPairE },
        { name := "rotate71", arity := 2, body := rotate71E },
        { name := "reflect59", arity := 2, body := reflect59E },
        { name := "dual47", arity := 2, body := dual47E } ] }

/-- The bytes of `kant_kernel.wasm`. -/
def kernelBytes : ByteArray := Encode.moduleBytes kernelModule

/-- Every function of the kernel is well formed: no out-of-range local, no
literal that a signed 64-bit constant cannot hold, no possible trap. -/
theorem kernelModule_wf : Module.Wf kernelModule :=
  Module.wf_of_wfb (by decide)

end Kant.Wasm.Kernel
