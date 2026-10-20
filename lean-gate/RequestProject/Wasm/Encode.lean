/-
# The WebAssembly binary format: emitting a `.wasm` module from Lean

This is the encoder proper — the part of `argumentcomputer/Wasm.lean`
(`Wasm/Bytes.lean`) that turns an abstract module into the bytes of a
`.wasm` file — re-implemented for the fragment of
`RequestProject.Wasm.Syntax` and for the current toolchain.

The layout follows the WebAssembly core specification, release 2.0,
section 5 (Binary Format):

```
magic  = 00 61 73 6D          ("\0asm")
version= 01 00 00 00
type    section (id 1)  : the function signatures
function section (id 3) : signature index of every function
export  section (id 7)  : every function is exported under its name
code    section (id 10) : the compiled bodies
```

Every function of the module has signature `(i64 …) -> (i64)`, so the type
section holds one signature per function and the function section is the
identity map.
-/
import RequestProject.Wasm.Syntax
import RequestProject.Wasm.Leb128

namespace Kant.Wasm.Encode

open Kant.Wasm.Leb128

/-- Byte string abbreviation. -/
abbrev Bytes := List UInt8

/-- Encoding of a vector: its length in unsigned LEB128, then the items. -/
def vec (items : List Bytes) : Bytes :=
  uleb items.length ++ items.flatten

/-- Encoding of a section: the id byte, the size of the payload, the payload. -/
def sec (id : Nat) (content : Bytes) : Bytes :=
  UInt8.ofNat id :: (uleb content.length ++ content)

/-- Encoding of a name: a vector of its UTF-8 bytes. -/
def name (s : String) : Bytes :=
  let bs := s.toUTF8.toList
  uleb bs.length ++ bs

/-- The value type `i64`. -/
def i64Byte : UInt8 := 0x7E

/-- Opcode of a binary arithmetic instruction. -/
def binOpcode : BinOp → UInt8
  | .add => 0x7C
  | .sub => 0x7D
  | .mul => 0x7E
  | .divu => 0x80
  | .remu => 0x82
  | .and => 0x83
  | .or => 0x84
  | .xor => 0x85
  | .shl => 0x86
  | .shru => 0x88

/-- Opcode of an unsigned comparison instruction. -/
def cmpOpcode : CmpOp → UInt8
  | .eq => 0x51
  | .ne => 0x52
  | .ltu => 0x54
  | .gtu => 0x56
  | .leu => 0x58
  | .geu => 0x5A

/-- Encoding of a single instruction. -/
def instr : Instr → Bytes
  | .i64const n => 0x42 :: sleb n
  | .localGet i => 0x20 :: uleb i
  | .binop op => [binOpcode op]
  | .cmpop op => [cmpOpcode op]
  | .extendU => [0xAD]

/-- Encoding of an instruction sequence. -/
def instrs (is : List Instr) : Bytes := (is.map instr).flatten

/-- The signature `(i64 … i64) -> (i64)` of a function of `arity` parameters. -/
def funcType (arity : Nat) : Bytes :=
  0x60 :: (uleb arity ++ List.replicate arity i64Byte ++ uleb 1 ++ [i64Byte])

/-- The code entry of a function: no extra locals, the body, `end`. -/
def code (f : Func) : Bytes :=
  let body := uleb 0 ++ instrs f.body.compile ++ [0x0B]
  uleb body.length ++ body

/-- Payload of the type section: one signature per function. -/
def typePayload (m : Module) : Bytes :=
  vec (m.funcs.map fun f => funcType f.arity)

/-- Payload of the function section: function `i` has signature `i`. -/
def funcPayload (m : Module) : Bytes :=
  vec ((List.range m.funcs.length).map uleb)

/-- Payload of the export section: every function is exported under its name. -/
def exportPayload (m : Module) : Bytes :=
  vec ((m.funcs.zipIdx).map fun (f, i) => name f.name ++ (0x00 : UInt8) :: uleb i)

/-- Payload of the code section. -/
def codePayload (m : Module) : Bytes :=
  vec (m.funcs.map code)

/-- The type section. -/
def typeSection (m : Module) : Bytes := sec 1 (typePayload m)

/-- The function section. -/
def funcSection (m : Module) : Bytes := sec 3 (funcPayload m)

/-- The export section. -/
def exportSection (m : Module) : Bytes := sec 7 (exportPayload m)

/-- The code section. -/
def codeSection (m : Module) : Bytes := sec 10 (codePayload m)

/-- `"\0asm"`, the wasm magic number. -/
def magic : Bytes := [0x00, 0x61, 0x73, 0x6D]

/-- Binary-format version 1. -/
def version : Bytes := [0x01, 0x00, 0x00, 0x00]

/-- **The extractor**: the bytes of the `.wasm` file for a module. -/
def module (m : Module) : Bytes :=
  magic ++ version ++ typeSection m ++ funcSection m ++ exportSection m ++ codeSection m

/-- The emitted file is a `ByteArray` ready to be written to disk. -/
def moduleBytes (m : Module) : ByteArray := ⟨(module m).toArray⟩

/-! ## Structural guarantees about the emitted bytes -/

/-- Every emitted file starts with the wasm magic number and version. -/
theorem module_prefix (m : Module) :
    (module m).take 8 = [0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00] := by
  simp [module, magic, version]

/-- A section starts with its id byte. -/
theorem sec_head (id : Nat) (content : Bytes) :
    (sec id content).head? = some (UInt8.ofNat id) := rfl

/-- The sections appear in the order the binary format requires
(type = 1, function = 3, export = 7, code = 10), each carrying its own
payload. -/
theorem module_sections (m : Module) :
    module m = magic ++ version ++ sec 1 (typePayload m) ++ sec 3 (funcPayload m)
      ++ sec 7 (exportPayload m) ++ sec 10 (codePayload m) := rfl

/-- The export section names exactly the functions of the module, in order. -/
theorem exportSection_names (m : Module) :
    exportSection m =
      sec 7 (uleb m.funcs.length ++
        ((m.funcs.zipIdx).map fun (f, i) => name f.name ++ (0x00 : UInt8) :: uleb i).flatten) := by
  simp [exportSection, exportPayload, vec]

end Kant.Wasm.Encode
