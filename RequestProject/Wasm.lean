/-
# `RequestProject.Wasm` — extracting the Kant kernel to WebAssembly

A self-contained WebAssembly back end for the Lean port:

* `RequestProject.Wasm.Leb128` — the binary format's integer encoding,
  with round-trip proofs;
* `RequestProject.Wasm.Syntax` — the instruction fragment and the
  expression language compiled into it;
* `RequestProject.Wasm.Semantics` — the wasm stack machine and the
  compiler correctness theorem;
* `RequestProject.Wasm.Encode` — the emitter for the `.wasm` binary format;
* `RequestProject.Wasm.Kernel` — the Kant kernel as a wasm module;
* `RequestProject.Wasm.KernelSpec` — each exported function computes the
  corresponding `Kant.*` definition;
* `RequestProject.Wasm.Extraction` — the three layers combined.

`lake exe emitwasm dist` writes the binary; `node web/wasm-test.mjs`
checks it in a real WebAssembly engine.
-/
import RequestProject.Wasm.Leb128
import RequestProject.Wasm.Syntax
import RequestProject.Wasm.Semantics
import RequestProject.Wasm.Encode
import RequestProject.Wasm.Kernel
import RequestProject.Wasm.KernelSpec
import RequestProject.Wasm.Extraction
