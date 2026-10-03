/-
# `packdomain` — turn a corpus scan into the domain data package

`lake exe packdomain [scanfile] [outdir] [--tables] [--shard-size=N]` reads the
canonical scan written by `lake exe emitdomain`, builds the domain graph with
`Kant.Dom.catalog`, and writes the package of §24 with the encoders proved
correct in `RequestProject/Kant/Domain/`.  With `--tables` it writes the
relational projection only — the same graph (`tablesPackage_recovers`), in files
that stay small for a corpus of thousands of declarations.  It then reads every
file back, compares the graph, and fails if anything differs.

With `--shard-size=N` the corpus is emitted as a partition (§8): the
declarations are cut into shards of `N`, and each shard is emitted, re-imported
and compared on its own.  This keeps every file inside the recursion depth the
decoder can handle, so a corpus of thousands of declarations can be emitted
*and* checked.  The dependency edges that cross a shard boundary are not part of
any shard's graph; they are written out separately, as `cross-shard-deps.csv`,
so the partition loses nothing.

It is a separate program from the scanner because it needs no environment:
the encoders are ordinary compiled Lean code.
-/
import RequestProject.Kant.Domain

open Kant.Codec
open Kant.Dom

/-- Write one file of the package. -/
def writePackageFile (dir : System.FilePath) (f : List Char × List Char) : IO Unit :=
  IO.FS.writeFile (dir / String.ofList f.1) (String.ofList f.2)

/-- The description carried by the catalog of this project's corpus. -/
def corpusDescription : String :=
  "every declaration of the Lean corpus of this project, its statement, the proof that " ++
    "establishes it, the axioms that proof rests on, and what it consumes and produces"

/-- Report the coverage of a graph on stdout. -/
def reportSummary (dom : Domain) : IO Unit := do
  let s := summary dom
  IO.println s!"objects {s.objects}: proven {s.proven}, partially proven {s.partiallyProven}, \
unproven {s.unproven}, contradicted {s.contradicted}"
  IO.println s!"proofs {s.proofs}: valid {s.validProofs}"
  IO.println s!"canonical hash {String.ofList dom.hash}"
  (← IO.getStdout).flush

/-- Emit a package into `dir`, read it back, and say whether it decoded to the
graph it came from. -/
def emitAndCheck (dir : System.FilePath) (dom : Domain) (tablesOnly : Bool) (chatty : Bool) :
    IO Bool := do
  IO.FS.createDirAll dir
  let files := if tablesOnly then tablesPackage dom else package dom
  for f in files do
    writePackageFile dir f
    if chatty then
      IO.println s!"wrote {String.ofList f.1} ({(String.ofList f.2).length} characters)"
      (← IO.getStdout).flush
  let read := if tablesOnly then tablesPackageRead files else packageRead files
  pure (read.map Domain.text == some dom.text)

/-- Restrict every declaration's dependencies to the names the shard contains,
and collect the edges that were cut. -/
def restrictShard (names : Std.HashSet String) (ds : List Decl) :
    List Decl × List (String × String) :=
  ds.foldr (init := ([], [])) fun d acc =>
    let inside := fun (n : List Char) => names.contains (String.ofList n)
    let kept := d.deps.filter inside
    let cut := (d.deps.filter (fun n => !inside n)).map
      (fun n => (String.ofList d.name, String.ofList n))
    ({ d with deps := kept } :: acc.1, cut ++ acc.2)

/-- Pad a shard number so the directories sort. -/
def shardName (i : Nat) : String :=
  let s := toString i
  "shard-" ++ "".pushn '0' (3 - min 3 s.length) ++ s

/-- Emit the corpus as a verified partition. -/
def emitShards (outdir : System.FilePath) (decls : List Decl) (size : Nat) : IO Unit := do
  let shards := List.toChunks (max size 1) decls
  IO.println s!"partitioning {decls.length} declarations into {shards.length} shards \
of at most {max size 1}"
  (← IO.getStdout).flush
  let mut rows : List (List (List Char)) := []
  let mut crossEdges : List (String × String) := []
  let mut allOk := true
  for (shard, i) in shards.zipIdx do
    let names : Std.HashSet String :=
      shard.foldl (fun acc d => acc.insert (String.ofList d.name)) ∅
    let (closedShard, cut) := restrictShard names shard
    let name := shardName i
    let dom := catalog s!"kant-zk-pastebin/{name}".toList
      (corpusDescription ++ s!" — shard {i + 1} of {shards.length}").toList closedShard
    let ok ← emitAndCheck (outdir / name) dom true false
    let s := summary dom
    allOk := allOk && ok
    crossEdges := crossEdges ++ cut
    rows := rows ++ [[name.toList, s!"{s.objects}".toList, s!"{s.proven}".toList,
      s!"{s.unproven}".toList, s!"{s.proofs}".toList, s!"{s.validProofs}".toList,
      dom.hash, (if ok then "RECOVERED" else "MISMATCH").toList]]
    IO.println s!"{name}: {s.objects} objects, {s.proven} proven, hash \
{String.ofList dom.hash} — {if ok then "re-imported" else "MISMATCH"}"
    (← IO.getStdout).flush
  let index := tableText
    ["shard".toList, "objects".toList, "proven".toList, "unproven".toList, "proofs".toList,
     "valid_proofs".toList, "canonical_hash".toList, "roundtrip".toList] rows
  IO.FS.writeFile (outdir / "shards.csv") (String.ofList index)
  let crossTable := tableText ["source_declaration".toList, "relation".toList,
      "target_declaration".toList]
    (crossEdges.map (fun e => [e.1.toList, "DEPENDS_ON".toList, e.2.toList]))
  IO.FS.writeFile (outdir / "cross-shard-deps.csv") (String.ofList crossTable)
  IO.println s!"wrote shards.csv and cross-shard-deps.csv ({crossEdges.length} edges \
crossing a shard boundary)"
  if !allOk then
    throw (IO.userError "a shard did not decode back to the canonical graph")

def main (args : List String) : IO Unit := do
  let positional := args.filter (fun a => !a.startsWith "--")
  let scanfile : System.FilePath := (positional.head?.getD "domain/corpus-scan.kant")
  let outdir : System.FilePath :=
    match positional.drop 1 with
    | d :: _ => d
    | [] => "domain"
  let text ← IO.FS.readFile scanfile
  let some scan := canonDecode text.toList
    | throw (IO.userError "the scan file is not canonical text")
  let some decls := scanOfVal scan
    | throw (IO.userError "the scan file is not a scan")
  IO.println s!"read {decls.length} declarations from {scanfile}"
  (← IO.getStdout).flush
  let shardSize : Option Nat :=
    (args.findSome? (fun a =>
      if a.startsWith "--shard-size=" then (a.drop "--shard-size=".length).toNat? else none))
  IO.FS.createDirAll outdir
  match shardSize with
  | some n => emitShards outdir decls n
  | none =>
    let dom := catalog "kant-zk-pastebin".toList corpusDescription.toList decls
    reportSummary dom
    let tablesOnly := args.contains "--tables"
    let ok ← emitAndCheck outdir dom tablesOnly true
    IO.println (if ok then "re-imported: the package decodes back to the canonical graph"
                else "re-imported: MISMATCH")
    let tablesOk := (domainOfTables (metaTable dom) (objectsTable dom) (proofsTable dom)
        (relationsTable dom)).map Domain.text == some dom.text
    IO.println (if tablesOk then "relational tables: rebuild the canonical graph"
                else "relational tables: MISMATCH")
    if !ok || !tablesOk then
      throw (IO.userError "the emitted package did not decode back to the canonical graph")
