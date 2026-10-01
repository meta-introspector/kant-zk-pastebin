# Extracting WebAssembly from Lean, without a C toolchain

`dist/kant_kernel.wasm` is a real, 799-byte WebAssembly binary that this
repository produces from Lean itself:

```
lake exe emitwasm dist      # writes dist/kant_kernel.wasm + dist/kernel-vectors.json
node web/wasm-test.mjs      # validates and runs it in a WebAssembly engine
```

No emscripten, no WASI SDK, no `clang`. The bytes are computed by a Lean
function (`Kant.Wasm.Encode.module`) and written to disk by a Lean
executable (`EmitWasm.lean`), which is a different route from the
Lean → C → emscripten path sketched in `WASM-AND-NETWORK.md` (that path is
still unbuilt here, and `scripts/build-wasm.sh` still refuses to run
without its toolchain).

## Provenance

The design follows [`argumentcomputer/Wasm.lean`](https://github.com/argumentcomputer/Wasm.lean),
which is a Lean 4 library for the WebAssembly binary format: `Wasm/Leb128.lean`
for the variable-length integers, `Wasm/Bytes.lean` for the module encoder,
`Wasm/Wast/AST.lean` for the abstract syntax. That library pins Lean
`nightly-2023-01-10` and depends on packages that no longer resolve against the
toolchain used here, so it could not be added as a dependency. The layers were
therefore re-derived from the WebAssembly core specification (release 2.0,
section 5, *Binary Format*) for the fragment this project needs — and, unlike
the original, each layer comes with proofs.

## The layers

| module | what it is | key results |
|---|---|---|
| `RequestProject/Wasm/Leb128.lean` | unsigned and signed LEB128 | `ulebDec_uleb`, `slebDec_sleb`: encoding then decoding is the identity, in a byte stream |
| `RequestProject/Wasm/Syntax.lean` | the instruction fragment, an expression language, and a decidable well-formedness check | `Expr.wf_of_wfb` |
| `RequestProject/Wasm/Semantics.lean` | the wasm stack machine over `UInt64` (`i64`), with traps as `Option` | `Expr.exec_compile` (compiler correctness), `Expr.eval_isSome_of_wf` (well-formed code cannot trap) |
| `RequestProject/Wasm/Encode.lean` | the `.wasm` binary format: magic, version, type/function/export/code sections | `module_prefix`, `module_sections` |
| `RequestProject/Wasm/Decode.lean` | a reader for that format, and a type checker for the decoded code | `decodeModule_module` (reading undoes writing), `typecheck_compile`, `module_validates` |
| `RequestProject/Wasm/Kernel.lean` | the Kant kernel as a wasm module | `kernelModule_wf` |
| `RequestProject/Wasm/KernelSpec.lean` | each exported function computes the corresponding `Kant.*` definition | `eval_hexDigitE`, `eval_mkCidE`, `eval_mergeCidsE`, `eval_creditsForE`, `eval_socialChunksE`, `eval_lsbEmbedE`, … |
| `RequestProject/Wasm/Extraction.lean` | the layers combined | `kernel_exec_total`, `kernelBytes_sections`, `kernelBytes_decodes`, `kernelBytes_validates` |

Read together they say: for every exported function, the bytes in the code
section are the compilation of an `Expr`; running those bytes on the stack
machine terminates without trapping and yields the value of that `Expr`; and
that value is the value of the Lean definition the pastebin is specified by.

## Why "invalid module" cannot be the binary's fault

A WebAssembly engine does two things to a module before it will run: it
*decodes* the byte string, and it *validates* the code it decoded. Both phases
have a counterpart proved here for the file `lake exe emitwasm` writes.

* **Decoding.** `Kant.Wasm.Decode.decodeModule` is a reader written against the
  binary format alone: it checks the magic number and version, each section id
  and declared size, every LEB128 field, every vector length, every opcode, and
  that nothing is left over. `decodeModule_module` proves that reading undoes
  writing — for any module, the reader recovers the arity of every signature,
  the identity function-to-type map, the export names in order with their
  indices, and the compiled body of every function. `kernelBytes_decodes` is
  that statement for the kernel, and three `#guard`s run the decoder on the
  actual bytes at build time.
* **Validation.** `typecheck` is the stack type checker of the specification's
  validation rules, restricted to this fragment. `typecheck_compile` proves
  that a well-formed expression compiles to a sequence that leaves exactly one
  `i64` on the stack — the result type the emitted signature declares — and
  `kernelBytes_validates` applies it to all twenty-one kernel functions.

So if a page reports the kernel as invalid, the bytes it received are not the
bytes in `dist/kant_kernel.wasm`. In practice that meant a 404 page: see
"Delivery" below.

`UInt64` is used for `i64` because Lean's `UInt64` arithmetic already *is*
wasm's `i64` arithmetic: wrapping add/sub/mul, unsigned div/rem (which trap on
zero — modelled by `Option`), and shifts that mask the shift amount modulo 64.

## The exported surface

Twenty-one `i64` functions, each proved against its Lean counterpart:

| export | Lean definition |
|---|---|
| `hex_digit` | `Kant.Bytes.hexDigit` |
| `cid_prefix`, `cid_type`, `cid_payload` | `Kant.Dasl.cidPrefix` / `cidType` / `cidPayload` |
| `mk_cid` | `Kant.Dasl.mkCid` (for `typ < 16`, `payload < 2^44`) |
| `merge_cids` | `Kant.Dasl.mergeCids` |
| `credits_for` | `Kant.Credits.creditsFor` |
| `capacity_bytes` | `Kant.Stego.capacityBytes` |
| `social_chunks` | the number of pieces `Kant.Sneakernet.chunk socialLimit` produces |
| `fits_social` | the 5 MB social-export bound |
| `lsb_embed`, `lsb_extract` | one step of `Kant.Stego.embedBits` / `extractBits` |
| `rotate71`, `reflect59`, `dual47` | the orbifold action of `Kant.Dasl` |
| `hex_hi`, `hex_lo` | the two digits of `Kant.Bytes.hexByte` |
| `fnv_offset`, `fnv1a_step` | `Kant.Bytes.fnvOffset` / `fnvStep` — the FNV-1a digest, one round at a time |
| `u64_byte` | `Kant.Bytes.u64Bytes`, the big-endian byte expansion |
| `cantor_pair` | `Nat.pair`, the pairing behind the Gödel numbering of code movies (31-bit inputs) |

`social_chunks` relies on `chunk_length_eq`, proved here: the chunker emits
exactly `⌈len / limit⌉ ` pieces.

## What is checked outside Lean

`lake exe emitwasm` also writes `dist/kernel-vectors.json`: the value of every
exported function on a fixed set of arguments, computed with the *Lean*
semantics of the emitted module. `node web/wasm-test.mjs` then

1. runs `WebAssembly.validate` on the binary (the engine's own validator
   accepts it),
2. instantiates it and checks all 59 golden vectors against the running
   engine,
3. checks 1024 stego round-trips directly against the binary, and
4. cross-checks the binary against `web/kantzk.mjs`, the JavaScript client,
   which `web/test.mjs` in turn pins to Lean-computed vectors — including the
   full `fnv1a` hash and `hexEncode` of several strings, driven from JS but
   computed step by step inside the binary.

So the agreement is three-way: Lean definitions, the extracted binary as run by
a real engine, and the browser client.

## Using it in a browser

```js
import { loadKernel } from "./kant-wasm.mjs";
const k = await loadKernel();            // see "Delivery" for where it looks
k.mergeCids(0xda51n << 48n, 12345n);     // BigInt in, unsigned BigInt out
k.witness(bytes);                        // hex digest, folded from the exports
k.source;                                // which copy was loaded
```

`web/index.html` does this on load: it reports the module size, the export count
and where the bytes came from in a status line and, whenever a paste is
addressed, recomputes the witness with the kernel and shows whether it agrees
with the JavaScript core.

## Delivery

The binary lives in `dist/`, one level above the document root of a deployment
that serves `web/`. A page served that way asks for `/dist/kant_kernel.wasm`,
gets the host's 404 body, and — in an earlier version of the loader, which
checked neither the HTTP status nor the wasm magic number — handed those bytes
straight to `WebAssembly.validate`, producing the thoroughly misleading

```
wasm kernel: unavailable (kant_kernel.wasm failed validation) — falling back to the JS core
```

Nothing was wrong with the module. Three changes make the report honest and the
kernel available anyway:

1. `web/kant-wasm.mjs` tries several locations (`../dist/kant_kernel.wasm`,
   `./kant_kernel.wasm`, `./dist/kant_kernel.wasm`), rejects a response that is
   not OK, is empty, or does not start with `\0asm`, and names the actual
   failure — `HTTP 404`, `not a wasm module (…)` — for every location it tried.
2. `web/kant-kernel-embedded.mjs` is a base64 copy of the same 799 bytes,
   generated by `node scripts/embed-kernel.mjs` after `lake exe emitwasm dist`
   and cached by the service worker as part of the application shell. The
   loader falls back to it, so the proved kernel also works from `file://`,
   offline, and on a host that ships only `web/`. `node web/wasm-test.mjs`
   fails if the embedded copy ever drifts from `dist/kant_kernel.wasm`.
3. `server/relay.mjs` serves `/dist/…` from the directory beside its static
   root, with `content-type: application/wasm`, so `--static web` publishes the
   real binary rather than the fallback.

Regenerating the kernel is therefore two commands:

```
lake exe emitwasm dist
node scripts/embed-kernel.mjs
```

## Scope, stated plainly

This extracts the pure 64-bit *arithmetic* kernel — the hot paths that every
other layer is built from. The fragment has no linear memory and no loops, so
the list- and string-processing definitions (`witness`, `frames`, `embedBlob`,
`godel`, …) are not themselves exported. Several of them are nonetheless
*computed* by the binary: `fnv1a`, the digest, the witness and hex encoding are folds over
the exported per-step functions, so the loop lives in the caller while every
arithmetic step is the verified one (`web/kant-wasm.mjs` does exactly that). Extending the
fragment with memory, `loop`/`br_if` and a matching semantics is the natural
next step, and the existing compiler-correctness proof is structured to be
extended rather than rewritten. Until then `web/kantzk.mjs` remains the
implementation of those functions in the client, checked against Lean vectors.
