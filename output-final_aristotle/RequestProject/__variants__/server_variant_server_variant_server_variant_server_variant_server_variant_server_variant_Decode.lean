/-
# Reading the emitted file back: the binary really is a wasm module

`RequestProject.Wasm.Encode` writes the bytes; this module reads them, and
proves that reading undoes writing.  That is the formal content of "the
binary is valid": a conforming consumer, given `dist/kant_kernel.wasm`,
recovers exactly the module Lean meant to emit — the same signatures, the
same function indices, the same export names, the same code — and finds no
trailing bytes.

Two independent checks are made here, matching the two phases a
WebAssembly engine performs on a module.

* **Decoding** (§ Decoder, `decodeModule_module`): every length prefix,
  section size, LEB128 field and opcode is parsed back, and the result is
  the encoded module.  A wrong section size or a truncated vector would
  make `decodeModule` return `none`.
* **Validation** (§ Type checking, `typecheck_compile`, `module_validates`):
  every function body is run through a stack type checker in the style of
  the specification's validation rules, and leaves exactly one `i64` on an
  initially empty stack — which is the result type the emitted signature
  declares.

The decoder returns *raw* data — names as UTF-8 bytes, `i64.const`
immediates as the `Int` a signed-LEB128 reader produces — so nothing is
assumed about the encoder beyond the bytes themselves.

Mathlib-free, like the rest of `RequestProject.Wasm`.
-/
import RequestProject.Wasm.Encode

namespace Kant.Wasm.Decode

open Kant.Wasm Kant.Wasm.Leb128 Kant.Wasm.Encode

/-- Byte string abbreviation. -/
abbrev Bytes := List UInt8

/-! ## What a decoder recovers -/

/-- An instruction as read back from the binary: the immediate of
`i64.const` is whatever a signed LEB128 reader returns. -/
inductive RawInstr
  | i64const (n : Int)
  | localGet (i : Nat)
  | binop (op : BinOp)
  | cmpop (op : CmpOp)
  | extendU
  deriving Repr, DecidableEq, Inhabited

/-- The raw form of an instruction of the abstract syntax. -/
def toRaw : Instr → RawInstr
  | .i64const n => .i64const (n : Int)
  | .localGet i => .localGet i
  | .binop op => .binop op
  | .cmpop op => .cmpop op
  | .extendU => .extendU

/-- Everything a decoder recovers from a module of this fragment: the
arity of each declared signature, the signature index of each function,
the export table (name bytes and function index), and the code. -/
structure RawModule where
  arities : List Nat
  funcIdx : List Nat
  exports : List (Bytes × Nat)
  codes : List (List RawInstr)
  deriving Repr, DecidableEq, Inhabited

/-! ## Byte-level parsers -/

/-- Expect a particular byte. -/
def tag (b : UInt8) : Bytes → Option Bytes
  | [] => none
  | c :: bs => if c = b then some bs else none

/-- Expect a particular byte string. -/
def tags : Bytes → Bytes → Option Bytes
  | [], bs => some bs
  | t :: ts, bs => match tag t bs with
    | some bs' => tags ts bs'
    | none => none

/-- Read exactly `n` bytes. -/
def bytesN : Nat → Bytes → Option (Bytes × Bytes)
  | 0, bs => some ([], bs)
  | _ + 1, [] => none
  | n + 1, b :: bs => match bytesN n bs with
    | some (xs, r) => some (b :: xs, r)
    | none => none

theorem tag_cons (b : UInt8) (bs : Bytes) : tag b (b :: bs) = some bs := by
  simp [tag]

theorem tags_append (ts rest : Bytes) : tags ts (ts ++ rest) = some rest := by
  induction ts with
  | nil => rfl
  | cons t ts ih => simp [tags, tag_cons, ih]

theorem bytesN_append (xs rest : Bytes) : bytesN xs.length (xs ++ rest) = some (xs, rest) := by
  induction xs with
  | nil => rfl
  | cons x xs ih => simp [bytesN, ih]

theorem bytesN_length {n : Nat} {bs xs r : Bytes} (h : bytesN n bs = some (xs, r)) :
    r.length + n = bs.length := by
  induction n generalizing bs xs r with
  | zero => cases h; simp
  | succ n ih =>
      cases bs with
      | nil => simp [bytesN] at h
      | cons b bs =>
          simp only [bytesN] at h
          cases hb : bytesN n bs with
          | none => rw [hb] at h; simp at h
          | some p =>
              rw [hb] at h
              obtain ⟨ys, r'⟩ := p
              simp only [Option.some.injEq, Prod.mk.injEq] at h
              obtain ⟨-, rfl⟩ := h
              have := ih hb
              simp only [List.length_cons]
              omega

/-- Read `n` items with a given item parser. -/
def itemsDec {α : Type} (item : Bytes → Option (α × Bytes)) :
    Nat → Bytes → Option (List α × Bytes)
  | 0, bs => some ([], bs)
  | n + 1, bs => match item bs with
    | some (a, bs') => match itemsDec item n bs' with
      | some (as, bs'') => some (a :: as, bs'')
      | none => none
    | none => none

/-- Read a vector: a LEB128 length, then that many items. -/
def vecDec {α : Type} (item : Bytes → Option (α × Bytes)) (bs : Bytes) :
    Option (List α × Bytes) :=
  match ulebDec bs with
  | some (n, bs') => itemsDec item n bs'
  | none => none

/-- The generic vector round trip: if the item parser undoes the item
encoder (up to the abstraction `f`), the vector parser undoes `vec`. -/
theorem vecDec_encode {α β : Type} {item : Bytes → Option (β × Bytes)}
    {enc : α → Bytes} {f : α → β}
    (h : ∀ a rest, item (enc a ++ rest) = some (f a, rest))
    (as : List α) (rest : Bytes) :
    vecDec item (vec (as.map enc) ++ rest) = some (as.map f, rest) := by
  have hlen : (as.map enc).length = as.length := by simp
  have key : ∀ (as : List α) (rest : Bytes),
      itemsDec item as.length ((as.map enc).flatten ++ rest) = some (as.map f, rest) := by
    intro as
    induction as with
    | nil => intro rest; rfl
    | cons a as ih =>
        intro rest
        simp only [List.map_cons, List.flatten_cons, List.length_cons, itemsDec,
          List.append_assoc, h a, ih rest]
  simp only [vec, hlen, List.append_assoc, ulebDec_uleb, vecDec, key as rest]

/-! ## Sections -/

/-- Read a section: the id byte, the payload size, then the payload, which
must be consumed exactly by the vector parser. -/
def secDec {α : Type} (id : Nat) (item : Bytes → Option (α × Bytes)) (bs : Bytes) :
    Option (List α × Bytes) :=
  match tag (UInt8.ofNat id) bs with
  | none => none
  | some bs =>
    match ulebDec bs with
    | none => none
    | some (sz, bs) =>
      match bytesN sz bs with
      | none => none
      | some (payload, rest) =>
        match vecDec item payload with
        | some (xs, []) => some (xs, rest)
        | _ => none

theorem secDec_sec {α β : Type} {item : Bytes → Option (β × Bytes)}
    {enc : α → Bytes} {f : α → β}
    (h : ∀ a rest, item (enc a ++ rest) = some (f a, rest))
    (id : Nat) (as : List α) (rest : Bytes) :
    secDec id item (sec id (vec (as.map enc)) ++ rest) = some (as.map f, rest) := by
  have hpay := vecDec_encode (item := item) (enc := enc) (f := f) h as []
  simp only [sec, List.cons_append, secDec, tag_cons, List.append_assoc, ulebDec_uleb,
    bytesN_append, List.append_nil] at *
  rw [hpay]

/-! ## Signatures -/

/-- Read a function signature, returning its arity.  Every parameter and
the single result must be `i64`. -/
def funcTypeDec (bs : Bytes) : Option (Nat × Bytes) :=
  match tag 0x60 bs with
  | none => none
  | some bs =>
    match ulebDec bs with
    | none => none
    | some (n, bs) =>
      match bytesN n bs with
      | none => none
      | some (ps, bs) =>
        if ps.all (· = i64Byte) then
          match ulebDec bs with
          | none => none
          | some (m, bs) =>
            if m = 1 then
              match bytesN m bs with
              | none => none
              | some (rs, bs) => if rs.all (· = i64Byte) then some (n, bs) else none
            else none
          else none

theorem bytesN_replicate (n : Nat) (b : UInt8) (rest : Bytes) :
    bytesN n (List.replicate n b ++ rest) = some (List.replicate n b, rest) := by
  simpa using bytesN_append (List.replicate n b) rest

theorem funcTypeDec_funcType (arity : Nat) (rest : Bytes) :
    funcTypeDec (funcType arity ++ rest) = some (arity, rest) := by
  simp only [funcType, List.cons_append, funcTypeDec, tag_cons, List.append_assoc,
    ulebDec_uleb, bytesN_replicate, List.nil_append]
  simp [bytesN, i64Byte]

/-! ## Exports -/

/-- Read an export entry: the name, the kind byte `0x00` (a function), and
the function index. -/
def exportDec (bs : Bytes) : Option ((Bytes × Nat) × Bytes) :=
  match ulebDec bs with
  | none => none
  | some (len, bs) =>
    match bytesN len bs with
    | none => none
    | some (nm, bs) =>
      match tag 0x00 bs with
      | none => none
      | some bs =>
        match ulebDec bs with
        | none => none
        | some (idx, bs) => some ((nm, idx), bs)

theorem exportDec_export (s : String) (i : Nat) (rest : Bytes) :
    exportDec ((name s ++ (0x00 : UInt8) :: uleb i) ++ rest)
      = some ((s.toUTF8.toList, i), rest) := by
  simp only [name, List.append_assoc, exportDec, ulebDec_uleb, bytesN_append,
    List.cons_append, tag_cons]

/-! ## Code -/

theorem ulebDec_shorter : ∀ {bs : Bytes} {n : Nat} {r : Bytes},
    ulebDec bs = some (n, r) → r.length < bs.length
  | [], _, _, h => by simp [ulebDec] at h
  | b :: bs, n, r, h => by
      simp only [ulebDec] at h
      by_cases hb : b.toNat < 128
      · rw [if_pos hb] at h
        cases h
        simp
      · rw [if_neg hb] at h
        cases hrec : ulebDec bs with
        | none => rw [hrec] at h; simp at h
        | some p =>
            rw [hrec] at h
            obtain ⟨n', r'⟩ := p
            simp only [Option.some.injEq, Prod.mk.injEq] at h
            obtain ⟨-, rfl⟩ := h
            have := ulebDec_shorter hrec
            simp only [List.length_cons]
            omega

theorem slebDec_shorter : ∀ {bs : Bytes} {n : Int} {r : Bytes},
    slebDec bs = some (n, r) → r.length < bs.length
  | [], _, _, h => by simp [slebDec] at h
  | b :: bs, n, r, h => by
      simp only [slebDec] at h
      by_cases hb : b.toNat < 128
      · rw [if_pos hb] at h
        cases h
        simp
      · rw [if_neg hb] at h
        cases hrec : slebDec bs with
        | none => rw [hrec] at h; simp at h
        | some p =>
            rw [hrec] at h
            obtain ⟨n', r'⟩ := p
            simp only [Option.some.injEq, Prod.mk.injEq] at h
            obtain ⟨-, rfl⟩ := h
            have := slebDec_shorter hrec
            simp only [List.length_cons]
            omega

/-- The arithmetic opcodes. -/
def binOpOf (b : UInt8) : Option BinOp :=
  if b = 0x7C then some .add
  else if b = 0x7D then some .sub
  else if b = 0x7E then some .mul
  else if b = 0x80 then some .divu
  else if b = 0x82 then some .remu
  else if b = 0x83 then some .and
  else if b = 0x84 then some .or
  else if b = 0x85 then some .xor
  else if b = 0x86 then some .shl
  else if b = 0x88 then some .shru
  else none

/-- The comparison opcodes. -/
def cmpOpOf (b : UInt8) : Option CmpOp :=
  if b = 0x51 then some .eq
  else if b = 0x52 then some .ne
  else if b = 0x54 then some .ltu
  else if b = 0x56 then some .gtu
  else if b = 0x58 then some .leu
  else if b = 0x5A then some .geu
  else none

/-- Read one instruction. -/
def instrDec : Bytes → Option (RawInstr × Bytes)
  | [] => none
  | b :: bs =>
    if b = 0x42 then
      match slebDec bs with
      | some (n, r) => some (.i64const n, r)
      | none => none
    else if b = 0x20 then
      match ulebDec bs with
      | some (i, r) => some (.localGet i, r)
      | none => none
    else if b = 0xAD then some (.extendU, bs)
    else match binOpOf b with
      | some op => some (.binop op, bs)
      | none =>
        match cmpOpOf b with
        | some op => some (.cmpop op, bs)
        | none => none

theorem instrDec_shorter {bs : Bytes} {i : RawInstr} {r : Bytes}
    (h : instrDec bs = some (i, r)) : r.length < bs.length := by
  cases bs with
  | nil => simp [instrDec] at h
  | cons b bs =>
      simp only [instrDec] at h
      split at h
      · cases hs : slebDec bs with
        | none => rw [hs] at h; simp at h
        | some p =>
            rw [hs] at h
            obtain ⟨n, r'⟩ := p
            simp only [Option.some.injEq, Prod.mk.injEq] at h
            obtain ⟨-, rfl⟩ := h
            have := slebDec_shorter hs
            simp only [List.length_cons]
            omega
      · split at h
        · cases hs : ulebDec bs with
          | none => rw [hs] at h; simp at h
          | some p =>
              rw [hs] at h
              obtain ⟨n, r'⟩ := p
              simp only [Option.some.injEq, Prod.mk.injEq] at h
              obtain ⟨-, rfl⟩ := h
              have := ulebDec_shorter hs
              simp only [List.length_cons]
              omega
        · split at h
          · cases h; simp
          · split at h
            · cases h; simp
            · split at h
              · cases h; simp
              · simp at h

/-- Read instructions up to and including the terminating `end` (`0x0B`). -/
def instrsDec : Bytes → Option (List RawInstr × Bytes)
  | [] => none
  | b :: bs =>
    if b = 0x0B then some ([], bs)
    else
      match hi : instrDec (b :: bs) with
      | some (i, r) =>
        have : r.length < (b :: bs).length := instrDec_shorter hi
        match instrsDec r with
        | some (is, r') => some (i :: is, r')
        | none => none
      | none => none
termination_by bs => bs.length

/-- Decoding one encoded instruction, whatever follows it. -/
theorem instrDec_instr (i : Instr) (rest : Bytes) :
    instrDec (instr i ++ rest) = some (toRaw i, rest) := by
  cases i with
  | i64const n => simp [instr, instrDec, slebDec_sleb, toRaw]
  | localGet k => simp [instr, instrDec, ulebDec_uleb, toRaw]
  | binop op => cases op <;> simp [instr, instrDec, binOpcode, binOpOf, toRaw]
  | cmpop op => cases op <;> simp [instr, instrDec, cmpOpcode, binOpOf, cmpOpOf, toRaw]
  | extendU => simp [instr, instrDec, toRaw]

/-- No instruction encoding begins with the `end` opcode, so the reader
never stops early. -/
theorem instrsDec_cons (i : Instr) (tail : Bytes) :
    instrsDec (instr i ++ tail) =
      match instrsDec tail with
      | some (is, r) => some (toRaw i :: is, r)
      | none => none := by
  have hd : ∃ b bs, instr i ++ tail = b :: bs ∧ b ≠ 0x0B := by
    cases i with
    | i64const n =>
        exact ⟨0x42, sleb n ++ tail, by simp [instr], by decide⟩
    | localGet k =>
        exact ⟨0x20, uleb k ++ tail, by simp [instr], by decide⟩
    | binop op =>
        refine ⟨binOpcode op, tail, by simp [instr], ?_⟩
        cases op <;> decide
    | cmpop op =>
        refine ⟨cmpOpcode op, tail, by simp [instr], ?_⟩
        cases op <;> decide
    | extendU => exact ⟨0xAD, tail, by simp [instr], by decide⟩
  obtain ⟨b, bs, hcons, hne⟩ := hd
  have hi : instrDec (b :: bs) = some (toRaw i, tail) := by
    rw [← hcons]; exact instrDec_instr i tail
  rw [hcons, instrsDec, if_neg hne]
  split
  · next i' r' heq =>
      rw [hi] at heq
      simp only [Option.some.injEq, Prod.mk.injEq] at heq
      obtain ⟨rfl, rfl⟩ := heq
      rfl
  · next heq =>
      rw [hi] at heq
      simp at heq

/-- The instruction sequence of a function body round-trips. -/
theorem instrsDec_instrs (is : List Instr) (rest : Bytes) :
    instrsDec (instrs is ++ (0x0B : UInt8) :: rest) = some (is.map toRaw, rest) := by
  induction is with
  | nil =>
      simp only [instrs, List.map_nil, List.flatten, List.nil_append]
      rw [instrsDec]
      simp
  | cons i is ih =>
      have : instrs (i :: is) ++ (0x0B : UInt8) :: rest
          = instr i ++ (instrs is ++ (0x0B : UInt8) :: rest) := by
        simp [instrs, List.append_assoc]
      rw [this, instrsDec_cons, ih]
      simp

/-- Read a code entry: its size, no extra locals, the body, the `end`
opcode, and nothing after it inside the entry. -/
def codeDec (bs : Bytes) : Option (List RawInstr × Bytes) :=
  match ulebDec bs with
  | none => none
  | some (sz, bs) =>
    match bytesN sz bs with
    | none => none
    | some (payload, rest) =>
      match ulebDec payload with
      | some (0, p) =>
        match instrsDec p with
        | some (is, []) => some (is, rest)
        | _ => none
      | _ => none

theorem codeDec_code (f : Func) (rest : Bytes) :
    codeDec (code f ++ rest) = some (f.body.compile.map toRaw, rest) := by
  have hsplit : code f ++ rest
      = uleb (uleb 0 ++ instrs f.body.compile ++ [(0x0B : UInt8)]).length
          ++ ((uleb 0 ++ instrs f.body.compile ++ [(0x0B : UInt8)]) ++ rest) := by
    simp [code, List.append_assoc]
  have hinner : ulebDec (uleb 0 ++ instrs f.body.compile ++ [(0x0B : UInt8)])
      = some (0, instrs f.body.compile ++ [(0x0B : UInt8)]) := by
    have h0 : uleb 0 ++ instrs f.body.compile ++ [(0x0B : UInt8)]
        = uleb 0 ++ (instrs f.body.compile ++ [(0x0B : UInt8)]) := by
      simp [List.append_assoc]
    rw [h0, ulebDec_uleb]
  have hbodyDec : instrsDec (instrs f.body.compile ++ [(0x0B : UInt8)])
      = some (f.body.compile.map toRaw, []) := instrsDec_instrs f.body.compile []
  rw [hsplit]
  simp only [codeDec, ulebDec_uleb, bytesN_append, hinner, hbodyDec]

/-! ## The module -/

/-- **The decoder**: read a `.wasm` file of this fragment back into the
data it was made from, checking the magic number, the version, the four
section headers and their sizes, that the function section is the identity
map into the type section, that every function is exported under a
distinct index, and that nothing follows the code section. -/
def decodeModule (bs : Bytes) : Option RawModule :=
  match tags (magic ++ version) bs with
  | none => none
  | some bs =>
    match secDec 1 funcTypeDec bs with
    | none => none
    | some (arities, bs) =>
      match secDec 3 ulebDec bs with
      | none => none
      | some (idxs, bs) =>
        match secDec 7 exportDec bs with
        | none => none
        | some (exps, bs) =>
          match secDec 10 codeDec bs with
          | none => none
          | some (codes, bs) =>
            let n := arities.length
            if bs = [] ∧ idxs = List.range n ∧ exps.map Prod.snd = List.range n
                ∧ codes.length = n then
              some { arities := arities, funcIdx := idxs, exports := exps, codes := codes }
            else none

/-- **Reading undoes writing.**  Every file emitted by `Encode.module` is
decoded, by a parser that knows only the binary format, into exactly the
module that was encoded: the arities of the signatures, the identity
function-to-type map, the export names in order with their indices, and the
compiled body of each function — with no bytes left over. -/
theorem decodeModule_module (m : Module) :
    decodeModule (Encode.module m) =
      some { arities := m.funcs.map Func.arity,
             funcIdx := List.range m.funcs.length,
             exports := m.funcs.zipIdx.map (fun p => (p.1.name.toUTF8.toList, p.2)),
             codes := m.funcs.map (fun f => f.body.compile.map toRaw) } := by
  have htype : ∀ rest, secDec 1 funcTypeDec (typeSection m ++ rest)
      = some (m.funcs.map Func.arity, rest) := by
    intro rest
    have := secDec_sec (item := funcTypeDec) (enc := fun a => funcType a) (f := fun a => a)
      (fun a r => funcTypeDec_funcType a r) 1 (m.funcs.map Func.arity) rest
    simpa [typeSection, typePayload, List.map_map, Function.comp] using this
  have hfunc : ∀ rest, secDec 3 ulebDec (funcSection m ++ rest)
      = some (List.range m.funcs.length, rest) := by
    intro rest
    have := secDec_sec (item := ulebDec) (enc := uleb) (f := fun a => a)
      (fun a r => ulebDec_uleb a r) 3 (List.range m.funcs.length) rest
    simpa [funcSection, funcPayload] using this
  have hexp : ∀ rest, secDec 7 exportDec (exportSection m ++ rest)
      = some (m.funcs.zipIdx.map (fun p => (p.1.name.toUTF8.toList, p.2)), rest) := by
    intro rest
    have := secDec_sec (item := exportDec)
      (enc := fun p : Func × Nat => name p.1.name ++ (0x00 : UInt8) :: uleb p.2)
      (f := fun p : Func × Nat => (p.1.name.toUTF8.toList, p.2))
      (fun p r => exportDec_export p.1.name p.2 r) 7 m.funcs.zipIdx rest
    simpa [exportSection, exportPayload] using this
  have hcode : ∀ rest, secDec 10 codeDec (codeSection m ++ rest)
      = some (m.funcs.map (fun f => f.body.compile.map toRaw), rest) := by
    intro rest
    have := secDec_sec (item := codeDec) (enc := code)
      (f := fun f : Func => f.body.compile.map toRaw)
      (fun f r => codeDec_code f r) 10 m.funcs rest
    simpa [codeSection, codePayload] using this
  have hcode0 : secDec 10 codeDec (codeSection m)
      = some (m.funcs.map (fun f => f.body.compile.map toRaw), []) := by
    simpa using hcode []
  have hidx : (m.funcs.zipIdx.map (fun p : Func × Nat => (p.1.name.toUTF8.toList, p.2))).map
      Prod.snd = List.range m.funcs.length := by
    simp [List.map_map, Function.comp_def, List.zipIdx_map_snd, List.range_eq_range']
  have hpre : Encode.module m = (magic ++ version)
      ++ (typeSection m ++ (funcSection m ++ (exportSection m ++ codeSection m))) := by
    simp [Encode.module, List.append_assoc]
  rw [hpre]
  simp only [decodeModule, tags_append, htype, hfunc, hexp, hcode0, List.length_map, hidx]
  simp

/-- Corollary: the emitted file is decodable at all — a conforming reader
does not choke on it. -/
theorem decodeModule_isSome (m : Module) : (decodeModule (Encode.module m)).isSome := by
  rw [decodeModule_module]; rfl

/-! ## Type checking (the validation phase) -/

/-- The value types this fragment uses. -/
inductive VType | i32 | i64
  deriving Repr, DecidableEq, Inhabited

/-- One step of the validation algorithm: the effect of an instruction on
the type stack, `none` if the instruction is ill typed there. -/
def stackStep (arity : Nat) : List VType → RawInstr → Option (List VType)
  | s, .i64const _ => some (.i64 :: s)
  | s, .localGet i => if i < arity then some (.i64 :: s) else none
  | .i64 :: .i64 :: s, .binop _ => some (.i64 :: s)
  | .i64 :: .i64 :: s, .cmpop _ => some (.i32 :: s)
  | .i32 :: s, .extendU => some (.i64 :: s)
  | _, _ => none

/-- Validate an instruction sequence against an initial type stack. -/
def typecheck (arity : Nat) : List VType → List RawInstr → Option (List VType)
  | s, [] => some s
  | s, i :: is => match stackStep arity s i with
    | some s' => typecheck arity s' is
    | none => none

theorem typecheck_append (arity : Nat) (s : List VType) (is js : List RawInstr) :
    typecheck arity s (is ++ js) =
      match typecheck arity s is with
      | some s' => typecheck arity s' js
      | none => none := by
  induction is generalizing s with
  | nil => rfl
  | cons i is ih =>
      simp only [List.cons_append, typecheck]
      cases stackStep arity s i with
      | none => rfl
      | some s' => exact ih s'

/-- **Every compiled body is well typed**: a well-formed expression
compiles to a sequence that consumes nothing and leaves one `i64` on the
stack, whatever is underneath. -/
theorem typecheck_compile {arity : Nat} : ∀ {e : Expr}, Expr.Wf arity e →
    ∀ s : List VType, typecheck arity s (e.compile.map toRaw) = some (.i64 :: s)
  | .const n, _, s => by simp [Expr.compile, toRaw, typecheck, stackStep]
  | .var i, h, s => by
      have hi : i < arity := h
      simp [Expr.compile, toRaw, typecheck, stackStep, hi]
  | .bin op a b, h, s => by
      obtain ⟨ha, hb, _⟩ := h
      simp only [Expr.compile, List.map_append, typecheck_append,
        typecheck_compile ha s, typecheck_compile hb (VType.i64 :: s)]
      simp [List.map_cons, toRaw, typecheck, stackStep]
  | .cmp op a b, h, s => by
      obtain ⟨ha, hb⟩ := h
      simp only [Expr.compile, List.map_append, typecheck_append,
        typecheck_compile ha s, typecheck_compile hb (VType.i64 :: s)]
      simp [List.map_cons, toRaw, typecheck, stackStep]

/-- **The emitted module validates.**  Reading the file back and running
the decoded code of every function through the type checker succeeds with a
single `i64` on the stack — the result type its emitted signature declares —
and the decoded arity is the arity that signature was built from. -/
theorem module_validates {m : Module} (hm : m.Wf) :
    ∃ d, decodeModule (Encode.module m) = some d ∧
      d.arities = m.funcs.map Func.arity ∧
      d.codes.length = d.arities.length ∧
      ∀ f ∈ m.funcs, typecheck f.arity [] (f.body.compile.map toRaw) = some [VType.i64] := by
  refine ⟨_, decodeModule_module m, by simp, by simp, ?_⟩
  intro f hf
  exact typecheck_compile (hm f hf) []

end Kant.Wasm.Decode
