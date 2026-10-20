/-
# A verified fragment of WebAssembly: syntax, expressions and compilation

The abstract syntax below is the fragment of the wasm instruction set that
the Kant kernel needs: 64-bit integer arithmetic, unsigned comparisons and
`local.get`.  It follows the shape used by `argumentcomputer/Wasm.lean`
(`Wasm/Wast/AST.lean`: a module is a list of functions, a function is a
list of instructions) but is cut down to a straight-line, statically typed
fragment for which we can give a complete semantics and a compiler
correctness proof.

* `Instr` — flat wasm instructions, exactly as they appear in a function body.
* `Expr` — a tree of `i64` operations over the function parameters.
* `Expr.compile` — the (postfix) instruction sequence for an `Expr`.

`RequestProject.Wasm.Semantics` proves that the compiled instruction
sequence evaluates on the wasm stack machine to the value of the `Expr`,
and `RequestProject.Wasm.Encode` turns modules into the wasm binary format.

Mathlib-free by design: this is the compute-only core that is extracted.
-/

namespace Kant.Wasm

/-- Binary `i64 → i64 → i64` operators. -/
inductive BinOp
  | add | sub | mul | divu | remu | and | or | xor | shl | shru
  deriving Repr, DecidableEq, Inhabited

/-- Unsigned `i64 → i64 → i32` comparison operators. -/
inductive CmpOp
  | eq | ne | ltu | gtu | leu | geu
  deriving Repr, DecidableEq, Inhabited

/-- The instructions of the fragment. -/
inductive Instr
  /-- `i64.const n` -/
  | i64const (n : Nat)
  /-- `local.get i` -/
  | localGet (i : Nat)
  /-- an `i64` binary arithmetic instruction -/
  | binop (op : BinOp)
  /-- an unsigned `i64` comparison, pushing an `i32` 0/1 -/
  | cmpop (op : CmpOp)
  /-- `i64.extend_i32_u` -/
  | extendU
  deriving Repr, DecidableEq, Inhabited

/-- Expressions over the parameters of a function, all of type `i64`. -/
inductive Expr
  /-- a literal, which must fit in 64 bits -/
  | const (n : Nat)
  /-- the `i`-th parameter -/
  | var (i : Nat)
  | bin (op : BinOp) (a b : Expr)
  /-- a comparison, zero-extended back to `i64` -/
  | cmp (op : CmpOp) (a b : Expr)
  deriving Repr, Inhabited

namespace Expr

/-- Postfix compilation of an expression to wasm instructions. -/
def compile : Expr → List Instr
  | .const n => [.i64const n]
  | .var i => [.localGet i]
  | .bin op a b => a.compile ++ b.compile ++ [.binop op]
  | .cmp op a b => a.compile ++ b.compile ++ [.cmpop op, .extendU]

/-- Well-formedness with respect to a function of `arity` parameters:
every variable is a declared parameter, every literal is non-negative as a
signed 64-bit number (the binary format encodes `i64.const` with *signed*
LEB128), and every division or remainder has a syntactically non-zero
divisor, so the function cannot trap. -/
def Wf (arity : Nat) : Expr → Prop
  | .const n => n < 2 ^ 63
  | .var i => i < arity
  | .bin op a b =>
      Wf arity a ∧ Wf arity b ∧
        ((op = .divu ∨ op = .remu) → ∃ k, b = .const k ∧ 0 < k ∧ k < 2 ^ 63)
  | .cmp _ a b => Wf arity a ∧ Wf arity b

/-- A decidable check for `Wf`. -/
def wfb (arity : Nat) : Expr → Bool
  | .const n => decide (n < 2 ^ 63)
  | .var i => decide (i < arity)
  | .bin op a b =>
      wfb arity a && wfb arity b &&
        (match op with
          | .divu | .remu =>
              match b with
              | .const k => decide (0 < k) && decide (k < 2 ^ 63)
              | _ => false
          | _ => true)
  | .cmp _ a b => wfb arity a && wfb arity b

theorem wf_of_wfb {arity : Nat} : ∀ {e : Expr}, wfb arity e = true → Wf arity e
  | .const n, h => by simpa [wfb, Wf] using h
  | .var i, h => by simpa [wfb, Wf] using h
  | .bin op a b, h => by
      simp only [wfb, Bool.and_eq_true] at h
      obtain ⟨⟨ha, hb⟩, hop⟩ := h
      refine ⟨wf_of_wfb ha, wf_of_wfb hb, ?_⟩
      intro hd
      rcases hd with hd | hd <;> subst hd <;> cases b <;> simp_all [wfb] <;>
        exact ⟨_, rfl, by omega, by omega⟩
  | .cmp op a b, h => by
      simp only [wfb, Bool.and_eq_true] at h
      exact ⟨wf_of_wfb h.1, wf_of_wfb h.2⟩

/-- Convenient notation for the arithmetic constructors. -/
@[inline] def add (a b : Expr) : Expr := .bin .add a b
@[inline] def sub (a b : Expr) : Expr := .bin .sub a b
@[inline] def mul (a b : Expr) : Expr := .bin .mul a b
@[inline] def divC (a : Expr) (k : Nat) : Expr := .bin .divu a (.const k)
@[inline] def modC (a : Expr) (k : Nat) : Expr := .bin .remu a (.const k)
@[inline] def xor (a b : Expr) : Expr := .bin .xor a b
@[inline] def andE (a b : Expr) : Expr := .bin .and a b
@[inline] def orE (a b : Expr) : Expr := .bin .or a b

end Expr

/-- A function of the emitted module: a name, a number of `i64`
parameters, and a body computing a single `i64` result. -/
structure Func where
  name : String
  arity : Nat
  body : Expr
  deriving Repr, Inhabited

/-- A function is well formed when its body is. -/
def Func.Wf (f : Func) : Prop := Expr.Wf f.arity f.body

/-- A module is a list of exported functions. -/
structure Module where
  funcs : List Func
  deriving Repr, Inhabited

def Module.Wf (m : Module) : Prop := ∀ f ∈ m.funcs, f.Wf

/-- A decidable check for `Module.Wf`. -/
def Module.wfb (m : Module) : Bool := m.funcs.all fun f => Expr.wfb f.arity f.body

theorem Module.wf_of_wfb {m : Module} (h : m.wfb = true) : m.Wf := by
  intro f hf
  have := List.all_eq_true.mp h f hf
  exact Expr.wf_of_wfb this

end Kant.Wasm
