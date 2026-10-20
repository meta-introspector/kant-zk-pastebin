/-
# Semantics of the wasm fragment, and compiler correctness

We give the standard wasm stack-machine semantics for the instruction
fragment of `RequestProject.Wasm.Syntax`, using Lean's `UInt64` for the
`i64` values (its arithmetic is already the wrapping arithmetic wasm
prescribes, and its shifts already mask the shift amount modulo 64).

Division and remainder by zero *trap* in wasm, which is modelled by
`Option`.  The main results are

* `Expr.exec_compile` — the compiled instruction sequence pushes exactly
  the value of the expression onto the stack (compiler correctness), and
* `Expr.eval_isSome_of_wf` — a well-formed expression never traps,

so a well-formed `Func` is a total `i64 → … → i64` function.
-/
import RequestProject.Wasm.Syntax

namespace Kant.Wasm

/-- Semantics of the binary operators.  `divu`/`remu` trap on a zero
divisor; everything else is total. -/
def BinOp.apply : BinOp → UInt64 → UInt64 → Option UInt64
  | .add, a, b => some (a + b)
  | .sub, a, b => some (a - b)
  | .mul, a, b => some (a * b)
  | .divu, a, b => if b = 0 then none else some (a / b)
  | .remu, a, b => if b = 0 then none else some (a % b)
  | .and, a, b => some (a &&& b)
  | .or, a, b => some (a ||| b)
  | .xor, a, b => some (a ^^^ b)
  | .shl, a, b => some (a <<< b)
  | .shru, a, b => some (a >>> b)

/-- Semantics of the unsigned comparisons: an `i32` boolean, `0` or `1`. -/
def CmpOp.apply : CmpOp → UInt64 → UInt64 → UInt64
  | .eq, a, b => if a = b then 1 else 0
  | .ne, a, b => if a ≠ b then 1 else 0
  | .ltu, a, b => if a < b then 1 else 0
  | .gtu, a, b => if b < a then 1 else 0
  | .leu, a, b => if a ≤ b then 1 else 0
  | .geu, a, b => if b ≤ a then 1 else 0

/-- One step of the stack machine. -/
def step (locals : List UInt64) : Instr → List UInt64 → Option (List UInt64)
  | .i64const n, st => some (UInt64.ofNat n :: st)
  | .localGet i, st => (locals[i]?).map (· :: st)
  | .binop op, b :: a :: st => (op.apply a b).map (· :: st)
  | .binop _, _ => none
  | .cmpop op, b :: a :: st => some (op.apply a b :: st)
  | .cmpop _, _ => none
  | .extendU, v :: st => some (v :: st)
  | .extendU, [] => none

/-- Running a straight-line instruction sequence. -/
def exec (locals : List UInt64) : List Instr → List UInt64 → Option (List UInt64)
  | [], st => some st
  | i :: is, st => match step locals i st with
      | some st' => exec locals is st'
      | none => none

theorem exec_append (locals : List UInt64) (is js : List Instr) (st : List UInt64) :
    exec locals (is ++ js) st = (exec locals is st).bind (exec locals js) := by
  induction is generalizing st with
  | nil => simp [exec]
  | cons i is ih =>
      simp only [List.cons_append, exec]
      cases hstep : step locals i st with
      | none => simp
      | some st' => simp [ih]

namespace Expr

/-- Denotational value of an expression in an environment of parameters. -/
def eval (locals : List UInt64) : Expr → Option UInt64
  | .const n => some (UInt64.ofNat n)
  | .var i => locals[i]?
  | .bin op a b => do
      let x ← eval locals a
      let y ← eval locals b
      op.apply x y
  | .cmp op a b => do
      let x ← eval locals a
      let y ← eval locals b
      pure (op.apply x y)

/-- **Compiler correctness.**  The compiled instruction sequence leaves
exactly the value of the expression on top of the stack, and traps exactly
when the expression does. -/
theorem exec_compile (locals : List UInt64) (e : Expr) (st : List UInt64) :
    exec locals e.compile st = (eval locals e).map (· :: st) := by
  induction e generalizing st with
  | const n => simp [compile, exec, step, eval]
  | var i =>
      cases h : locals[i]? <;> simp [compile, exec, step, eval, h, Option.map]
  | bin op a b iha ihb =>
      simp only [compile, exec_append, iha, eval]
      cases hva : eval locals a with
      | none => simp
      | some x =>
          cases hvb : eval locals b with
          | none => simp [ihb, hvb]
          | some y =>
              cases hop : op.apply x y <;>
                simp [ihb, hvb, hop, exec, step]
  | cmp op a b iha ihb =>
      simp only [compile, exec_append, iha, eval]
      cases hva : eval locals a with
      | none => simp
      | some x =>
          cases hvb : eval locals b with
          | none => simp [ihb, hvb]
          | some y => simp [ihb, hvb, exec, step]

/-- A well-formed expression, evaluated in an environment providing all
declared parameters, never traps. -/
theorem eval_isSome_of_wf {arity : Nat} {locals : List UInt64} (hlen : arity ≤ locals.length)
    {e : Expr} (hwf : Wf arity e) : (eval locals e).isSome := by
  induction e with
  | const n => simp [eval]
  | var i =>
      have : i < locals.length := Nat.lt_of_lt_of_le hwf hlen
      simp [eval, List.getElem?_eq_getElem this]
  | bin op a b iha ihb =>
      obtain ⟨hwa, hwb, hdiv⟩ := hwf
      obtain ⟨x, hx⟩ := Option.isSome_iff_exists.mp (iha hwa)
      obtain ⟨y, hy⟩ := Option.isSome_iff_exists.mp (ihb hwb)
      have hnz : (op = .divu ∨ op = .remu) → y ≠ 0 := by
        intro hd
        obtain ⟨k, hk, hk0, hklt⟩ := hdiv hd
        have hklt' : k < 2 ^ 64 := by omega
        subst hk
        have hyk : y = UInt64.ofNat k := by
          simpa [eval] using hy.symm
        subst hyk
        intro hzero
        have hk : (UInt64.ofNat k).toNat = 0 := by rw [hzero]; rfl
        simp [Nat.mod_eq_of_lt hklt'] at hk
        omega
      cases op <;>
        simp_all [eval, BinOp.apply]
  | cmp op a b iha ihb =>
      obtain ⟨hwa, hwb⟩ := hwf
      obtain ⟨x, hx⟩ := Option.isSome_iff_exists.mp (iha hwa)
      obtain ⟨y, hy⟩ := Option.isSome_iff_exists.mp (ihb hwb)
      simp [eval, hx, hy]

end Expr

end Kant.Wasm
