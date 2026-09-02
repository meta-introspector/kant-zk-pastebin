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
  four sections in the order the format prescribes (`kernelBytes_prefix`).
-/
import RequestProject.Wasm.Kernel
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

end Kant.Wasm.Kernel
