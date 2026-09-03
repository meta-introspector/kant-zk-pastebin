/-
# The extraction, end to end

This module ties the three layers together for the module that
`lake exe emitwasm` actually writes:

* every exported function runs to completion on the wasm stack machine and
  returns exactly one `i64` (`kernel_exec_total`);
* the value it returns is the value of its `Expr` (`Expr.exec_compile`),
  which `RequestProject.Wasm.KernelSpec` identifies with the corresponding
  `Kant.*` definition;
* the emitted file is a WebAssembly binary: magic number, version, and the
  four sections in the order the format prescribes (`kernelBytes_prefix`),
  it decodes back to the module it was made from (`kernelBytes_decodes`),
  and its code passes a type checker (`kernelBytes_validates`) — so a
  consumer that reports the file as invalid is not reading this file.
-/
import RequestProject.Wasm.Kernel
import RequestProject.Wasm.Decode
import RequestProject.Wasm.Semantics

namespace Kant.Wasm.Kernel

open Kant.Wasm

/-- Every exported kernel function terminates without trapping and leaves a
single `i64` on the stack, namely the value of its expression. -/
theorem kernel_exec_total (f : Func) (hf : f ∈ kernelModule.funcs)
    (locals : List UInt64) (hlen : f.arity ≤ locals.length) :
    ∃ v, exec locals (Expr.compile f.body) [] = some [v] ∧ Expr.eval locals f.body = some v := by
  have hwf : Expr.Wf f.arity f.body := kernelModule_wf f hf
  obtain ⟨v, hv⟩ := Option.isSome_iff_exists.mp (Expr.eval_isSome_of_wf hlen hwf)
  exact ⟨v, by rw [Expr.exec_compile, hv]; rfl, hv⟩

/-- The emitted file starts with the WebAssembly magic number and version. -/
theorem kernelBytes_prefix :
    (Encode.module kernelModule).take 8 = [0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00] :=
  Encode.module_prefix kernelModule

/-- The emitted file is the magic number, the version, and the type,
function, export and code sections, in that order. -/
theorem kernelBytes_sections :
    Encode.module kernelModule =
      Encode.magic ++ Encode.version
        ++ Encode.sec 1 (Encode.typePayload kernelModule)
        ++ Encode.sec 3 (Encode.funcPayload kernelModule)
        ++ Encode.sec 7 (Encode.exportPayload kernelModule)
        ++ Encode.sec 10 (Encode.codePayload kernelModule) :=
  Encode.module_sections kernelModule

/-- **The emitted file decodes.**  A reader of the binary format recovers
from `dist/kant_kernel.wasm` exactly the module Lean encoded: the arity of
every signature, the identity function-to-type map, the export names in
order, and the compiled body of every function, with no trailing bytes. -/
theorem kernelBytes_decodes :
    Decode.decodeModule (Encode.module kernelModule) =
      some { arities := kernelModule.funcs.map Func.arity,
             funcIdx := List.range kernelModule.funcs.length,
             exports := kernelModule.funcs.zipIdx.map
               (fun p => (p.1.name.toUTF8.toList, p.2)),
             codes := kernelModule.funcs.map
               (fun f => f.body.compile.map Decode.toRaw) } :=
  Decode.decodeModule_module kernelModule

/-- **The emitted code validates.**  Every exported function's body passes
the stack type checker and leaves exactly one `i64`, the result type its
signature declares. -/
theorem kernelBytes_validates (f : Func) (hf : f ∈ kernelModule.funcs) :
    Decode.typecheck f.arity [] (f.body.compile.map Decode.toRaw)
      = some [Decode.VType.i64] :=
  Decode.typecheck_compile (kernelModule_wf f hf) []

-- Build-time checks on the bytes actually written to disk: they parse, they
-- carry all twenty-one exports, and every signature has a body.
#guard (Decode.decodeModule (Encode.module kernelModule)).isSome

#guard ((Decode.decodeModule (Encode.module kernelModule)).map
  fun d => d.exports.length) = some 21

#guard ((Decode.decodeModule (Encode.module kernelModule)).map
  fun d => decide (d.arities.length = d.codes.length)) = some true

end Kant.Wasm.Kernel
