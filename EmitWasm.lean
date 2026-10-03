/-
# `emitwasm` — extract the Kant kernel to a `.wasm` binary

Running `lake exe emitwasm [outdir]` writes

* `<outdir>/kant_kernel.wasm` — the WebAssembly binary produced by the
  verified encoder of `RequestProject.Wasm.Encode`, and
* `<outdir>/kernel-vectors.json` — golden vectors obtained by running the
  Lean *semantics* of the same module (`Kant.Wasm.exec`) on a fixed set of
  arguments.

`web/wasm-test.mjs` instantiates the binary in a real WebAssembly engine
and checks it against those vectors, so the toolchain is validated
end-to-end: Lean definition → verified compiler → binary → engine.
-/
import RequestProject.Wasm.Kernel
import RequestProject.Wasm.Semantics

open Kant.Wasm
open Kant.Wasm.Kernel

/-- Arguments each exported function is exercised with. -/
def testArgs : List (String × List (List Nat)) :=
  [ ("hex_digit", [[0], [9], [10], [15]]),
    ("cid_prefix", [[0xDA51 * 2 ^ 48 + 12345], [0]]),
    ("cid_type", [[0xDA51 * 2 ^ 48 + 3 * 2 ^ 44 + 7], [0]]),
    ("cid_payload", [[0xDA51 * 2 ^ 48 + 3 * 2 ^ 44 + 7], [2 ^ 44 - 1]]),
    ("mk_cid", [[3, 7], [5, 2 ^ 44 - 1]]),
    ("merge_cids", [[0xDA51 * 2 ^ 48 + 1, 0xDA51 * 2 ^ 48 + 3], [12345, 67890]]),
    ("credits_for", [[0], [1023], [1024], [5 * 1024 * 1024]]),
    ("capacity_bytes", [[0], [7], [8], [1000000]]),
    ("social_chunks", [[0], [1], [5 * 1024 * 1024], [5 * 1024 * 1024 + 1]]),
    ("fits_social", [[0], [5 * 1024 * 1024], [5 * 1024 * 1024 + 1]]),
    ("lsb_embed", [[200, 1], [201, 0], [255, 1]]),
    ("lsb_extract", [[200], [201]]),
    ("hex_hi", [[0], [15], [171], [255]]),
    ("hex_lo", [[0], [15], [171], [255]]),
    ("fnv_offset", [[]]),
    ("fnv1a_step", [[14695981039346656037, 0], [14695981039346656037, 104], [0, 255]]),
    ("u64_byte", [[0xdeadbeefcafebabe, 0], [0xdeadbeefcafebabe, 7], [0, 3]]),
    ("cantor_pair", [[0, 0], [1, 2], [2, 1], [1000, 999]]),
    ("rotate71", [[70, 1], [3, 5]]),
    ("reflect59", [[58, 1], [3, 5]]),
    ("dual47", [[46, 1], [3, 5]]) ]

/-- Value of an exported function under the Lean semantics of the emitted
module (`none` if it would trap). -/
def runKernel (fname : String) (args : List Nat) : Option UInt64 :=
  match kernelModule.funcs.find? (fun f => f.name == fname) with
  | none => none
  | some f => Expr.eval (args.map UInt64.ofNat) f.body

/-- The golden vectors as JSON. -/
def vectorsJson : String :=
  let entries := testArgs.flatMap fun (fname, argss) =>
    argss.map fun args =>
      let val := (runKernel fname args).getD 0
      "    {\"f\": \"" ++ fname ++ "\", \"args\": [" ++
        String.intercalate ", " (args.map fun a => "\"" ++ toString a ++ "\"") ++
        "], \"expected\": \"" ++ toString val.toNat ++ "\"}"
  "{\n  \"vectors\": [\n" ++ String.intercalate ",\n" entries ++ "\n  ]\n}\n"

def main (args : List String) : IO UInt32 := do
  let dir : System.FilePath := args.headD "dist"
  IO.FS.createDirAll dir
  let wasmPath := dir / "kant_kernel.wasm"
  let jsonPath := dir / "kernel-vectors.json"
  IO.FS.writeBinFile wasmPath kernelBytes
  IO.FS.writeFile jsonPath vectorsJson
  IO.println s!"wrote {wasmPath} ({kernelBytes.size} bytes)"
  IO.println s!"wrote {jsonPath} ({kernelModule.funcs.length} exported functions)"
  return 0
