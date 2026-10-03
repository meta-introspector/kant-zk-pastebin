/-
# The required test suite

The specification lists the cases every codec implementation must test.
This module runs each of them at elaboration time with `#guard`, on
concrete data, and states the ones that are general facts as theorems.

Covered, in the order the specification lists them: the empty object, a
minimal object, a nested object, multiple inputs, multiple outputs, a
missing field, an unknown field, an invalid type, malformed input,
Unicode, large numbers, null values, duplicate identifiers, references,
errors, warnings, partial proofs, failed proofs, successful proofs,
round-trip conversion and lossy conversion — followed by the
proof-specific cases: a known valid proof, a known invalid proof, a known
contradictory pair, a known incomplete proof, and a known incompatible
output.
-/
import Mathlib
import RequestProject.Kant.Codec.Exchange

set_option autoImplicit false
set_option relaxedAutoImplicit false

namespace Kant.Codec.Tests

open Kant.Codec

/-! ## Harness -/

/-- Every format the codec offers. -/
def allFormats : List Fmt := [.canonical, .yaml, .xml, .csv, .ipdl, .text, .unknown]

/-- One value survives one format. -/
def roundTrips (f : Fmt) (v : Val) : Bool :=
  (decodeVal f (encodeVal f v)).map canonEnc == some (canonEnc v)

/-- One value survives every format. -/
def roundTripsAll (v : Val) : Bool := allFormats.all (fun f => roundTrips f v)

/-- One proof object survives every format, as an object. -/
def objRoundTripsAll (o : Obj) : Bool :=
  allFormats.all (fun f => ((decodeVal f (encodeVal f o.toVal)).bind Obj.ofVal).map Obj.text
    == some o.text)

/-! ## The listed cases -/

/-- The empty object. -/
def tEmpty : Val := .obj []

#guard roundTripsAll tEmpty

/-- A minimal object: only the five required fields carry anything. -/
def tMinimal : Obj :=
  { (default : Obj) with
      id := "p1".toList
      kind := "theorem".toList
      status := .valid }

#guard objRoundTripsAll tMinimal

/-- A nested object. -/
def tNested : Val :=
  .obj [("a".toList, .obj [("b".toList, .list [.int 1, .obj [("c".toList, .str "d".toList)]])]),
        ("e".toList, .list [.list [.list [.null]]])]

#guard roundTripsAll tNested

/-- Multiple inputs and multiple outputs. -/
def tManyIO : Obj :=
  { (default : Obj) with
      id := "p2".toList
      kind := "factorisation".toList
      inputs :=
        [{ (default : Inp) with
             name := "n".toList
             type := "integer".toList
             value := .int 144 },
         { (default : Inp) with
             name := "matrix".toList
             type := "matrix".toList
             value := .list [.list [.int 1, .int 0], .list [.int 0, .int 1]] }]
      outputs :=
        [{ (default : Outp) with
             name := "factorization".toList
             type := "list".toList
             value := .list [.int 2, .int 2, .int 2, .int 2, .int 3, .int 3] },
         { (default : Outp) with
             name := "witness".toList
             type := "text".toList
             value := .str "144 = 2^4 * 3^2".toList }]
      status := .valid }

#guard objRoundTripsAll tManyIO
#guard tManyIO.inputs.length == 2 && tManyIO.outputs.length == 2

-- A missing field: a value that does not carry the required fields is not
-- a proof object, and the decoder says so rather than inventing one.
#guard (Obj.ofVal (.obj [])).isNone
#guard (Obj.ofVal (.obj [("id".toList, .str "p".toList)])).isNone

/-- An unknown field: whatever the sender knew and this reader does not
survives in the extension namespace. -/
def tUnknown : Obj :=
  { tMinimal with
      extensions := [("vendor.system_x".toList, .obj [("k".toList, .int 7)]),
                     ("experimental.foo".toList, .str "bar".toList)] }

#guard objRoundTripsAll tUnknown
#guard ((Obj.ofVal tUnknown.toVal).map (fun o => o.extensions.length)) == some 2

-- An invalid type: a field of the wrong type is a decode failure, not a
-- silent coercion.
#guard (Obj.ofVal (.obj [("id".toList, .int 1)])).isNone

/-- Malformed input: text that parses in no format is kept as raw text
rather than being called invalid. -/
def tMalformed : List Char := "Q>>> not any format <<<".toList

#guard (decodeVal .canonical tMalformed).isNone
#guard detect none tMalformed == Fmt.text
#guard (importAny none tMalformed).sourceData == tMalformed
#guard (importAny none tMalformed).status != Status.invalid

/-- Unicode. -/
def tUnicode : Val :=
  .obj [("greek".toList, .str "Ὠ φ ε".toList), ("han".toList, .str "定理".toList),
        ("emoji".toList, .str "🙂🧮".toList), ("combining".toList, .str "éé".toList)]

#guard roundTripsAll tUnicode

/-- Large numbers. -/
def tLarge : Val :=
  .list [.int 18446744073709551616, .int (-18446744073709551616),
         .int 170141183460469231731687303715884105727, .int 0]

#guard roundTripsAll tLarge

/-- Null values. -/
def tNulls : Val := .obj [("a".toList, .null), ("b".toList, .list [.null, .null])]

#guard roundTripsAll tNulls
#guard Val.isNull .null && !Val.isNull (.int 0)

/-- Duplicate identifiers: two fields under one key are preserved, in
order, rather than being quietly deduplicated. -/
def tDuplicate : Val := .obj [("k".toList, .int 1), ("k".toList, .int 2)]

#guard roundTripsAll tDuplicate
#guard (canonDecode (canonEnc tDuplicate)).map canonEnc == some (canonEnc tDuplicate)

/-- A reference: a construct the canonical model has no constructor for,
which the IPDL adapter carries in its reserved keys. -/
def tRef : Ipdl := .ref "obj-17".toList

/-- An annotation, likewise. -/
def tAnnot : Ipdl := .annot "author".toList "checked by hand".toList (.int 3)

#guard (ipdlRead (ipdlText tRef)).isSome
#guard (recover (project tRef)).isSome
#guard (recover (project tAnnot)).isSome

theorem refs_survive : recover (project tRef) = some tRef :=
  recover_project (.ref _)

theorem annots_survive : recover (project tAnnot) = some tAnnot :=
  recover_project (.annot _ _ _ (.int 3))

/-- Errors and warnings. -/
def tDiagnosed : Obj :=
  { tMinimal with
      errors :=
        [{ (default : Err) with
             code := "TYPE_MISMATCH".toList
             severity := .error
             field := "inputs[0].value".toList
             expected := "integer".toList
             actual := "string".toList
             recoverable := true }]
      warnings :=
        [{ (default : Err) with
             code := "COERCED".toList
             severity := .warning
             cause := "schema declares integer".toList
             resolution := "string to integer coercion".toList
             recoverable := true }] }

#guard objRoundTripsAll tDiagnosed
#guard tDiagnosed.errors.length == 1 && tDiagnosed.warnings.length == 1

/-- Partial proofs, failed proofs, successful proofs — and every other
status in the vocabulary. -/
def allStatuses : List Status :=
  [.unknown, .pending, .valid, .invalid, .partialResult, .error, .conflict, .unsupported]

#guard allStatuses.all (fun s => objRoundTripsAll { tMinimal with status := s })
#guard allStatuses.all (fun s => Status.ofName s.name == some s)

-- Round-trip conversion over everything above at once.
#guard [tEmpty, tNested, tUnicode, tLarge, tNulls, tDuplicate].all roundTripsAll
#guard [tMinimal, tManyIO, tUnknown, tDiagnosed].all objRoundTripsAll

/-- Lossy conversion: two objects differing only outside the minimal
profile project to the same thing, which is why the minimum declares
`PARTIAL`. -/
def tLossyA : Obj := { tMinimal with procedure := "replay".toList }

/-- The other side of that pair. -/
def tLossyB : Obj := { tMinimal with procedure := "recheck".toList }

#guard tLossyA.text != tLossyB.text
#guard canonEnc tLossyA.minimal == canonEnc tLossyB.minimal
#guard minimalProfileLossiness == Loss.partialLoss

/-! ## The proof-specific cases -/

/-- A known valid proof: `n = 144` in, `12` out. -/
def pValid : Obj :=
  { (default : Obj) with
      id := "proof-001".toList
      kind := "factorisation".toList
      inputs :=
        [{ (default : Inp) with
             name := "n".toList
             type := "integer".toList
             value := .int 144 }]
      outputs :=
        [{ (default : Outp) with
             name := "result".toList
             type := "integer".toList
             value := .int 12
             certificate := .str "12*12=144".toList }]
      status := .valid }

#guard objRoundTripsAll pValid
#guard validSemantics pValid
#guard compareObj pValid pValid == Verdict.equivalent

/-- A known invalid proof: it completed and failed validation, which is
not the same as an error. -/
def pInvalid : Obj := { pValid with status := .invalid }

#guard !validSemantics pInvalid
#guard compareObj pValid pInvalid == Verdict.different
#guard pInvalid.status != Status.error

/-- A known contradictory result: two systems both claim `VALID` and
disagree about the outputs. -/
def pOther : Obj :=
  { pValid with
      outputs :=
        [{ (default : Outp) with
             name := "result".toList
             type := "integer".toList
             value := .int 13
             certificate := .str "13*13=144".toList }] }

#guard compareObj pValid pOther == Verdict.conflict
#guard (diffVal [] pValid.toVal pOther.toVal).length != 0

/-- A known incomplete proof. -/
def pIncomplete : Obj := { pValid with status := .pending }

#guard compareObj pValid pIncomplete == Verdict.incomplete

/-- A known incompatible output: two objects of different kinds are not
comparable at all. -/
def pIncomparable : Obj := { pValid with kind := "primality".toList }

#guard compareObj pValid pIncomparable == Verdict.incomparable

/-! ## Golden vectors

The exact texts the JavaScript mirror in `web/kant-codec.mjs` is pinned
against, so the two implementations are known to agree byte for byte. -/

/-- The value both implementations serialise. -/
def gSample : Val :=
  .obj [("n".toList, .int 144), ("ok".toList, .bool true),
        ("xs".toList, .list [.null, .str "hi \"there\"".toList])]

#guard String.ofList (canonEnc gSample) == "O3;1;nI+144;2;okT2;xsL2;ZS10;hi \"there\""
#guard String.ofList (yamlEnc gSample)
  == "{\"n\": 144, \"ok\": true, \"xs\": [null, \"hi \\\"there\\\"\"]}"
#guard String.ofList (xmlEnc gSample)
  == "<obj><entry key=\"n\"><int>144</int></entry><entry key=\"ok\"><bool>true</bool></entry>\
      <entry key=\"xs\"><list><null/><str>hi &quot;there&quot;</str></list></entry></obj>"
#guard String.ofList (ipdlText (embed gSample))
  == "ipdl/1.0;O3;1;nI+144;2;okT2;xsL2;ZS10;hi \"there\""
#guard String.ofList (valHash gSample)
  == "3c796f2f2a0e2274900747be3ace4d77bc5d9611122ebd3a189b5d4c0c56bbbd"
#guard String.ofList (csvEncode gSample)
  == "object_id,object_type,field,value,value_type,parent_id\n\
      \"r\",\"object\",\"\",\"3\",\"count\",\"\"\n\
      \"r/0\",\"value\",\"n\",\"144\",\"integer\",\"r\"\n\
      \"r/1\",\"value\",\"ok\",\"true\",\"bool\",\"r\"\n\
      \"r/2\",\"list\",\"xs\",\"2\",\"count\",\"r\"\n\
      \"r/2/0\",\"value\",\"0\",\"\",\"null\",\"r/2\"\n\
      \"r/2/1\",\"value\",\"1\",\"hi \"\"there\"\"\",\"string\",\"r/2\"\n"

/-! ## The whole thing, end to end -/

-- The worked example of the specification, sealed, sent in each format,
-- opened, and compared against the original.
#guard allFormats.all (fun f =>
  match openEnvelope (sealEnvelope f "system-a".toList "system-b".toList 0 pValid) with
  | some o => compareObj pValid o == Verdict.equivalent
  | none => false)

-- Every export reports a passed round trip and a recorded conversion.
#guard allFormats.all (fun f =>
  (exportReport f pValid).roundTripped && !(exportReport f pValid).ledger.isEmpty)

end Kant.Codec.Tests
