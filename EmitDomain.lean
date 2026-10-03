/-
# `emitdomain` — run the skill on this project's own proof corpus

`lake exe emitdomain [outfile] [module-prefix]` is the *discovery* step of
§20 for the domain whose data is the Lean corpus of this project.  It
writes the scan as one canonical value (`Kant.Dom.scanVal`), which
`lake exe packdomain` then turns into the package — two programs, because
only this one needs the whole compiled environment in memory.

**Discover.**  It loads the compiled environment of `RequestProject` and
walks every declaration that came from one of its modules.  For each one
it records the name, the kind, the module and the line, the statement as
the pretty printer writes it, the axioms the kernel actually used, whether
`sorryAx` is among them, and which other declarations of the corpus it
mentions.  Nothing here is taken on trust from the source text: the axioms
come from the kernel, so `PROVEN` means the kernel says so.

The scan file round-trips (`Kant.Dom.scan_file_roundTrip`), so nothing is
lost between the two steps.
-/
import Lean
import RequestProject.Kant.Domain

open Lean
open Kant.Codec
open Kant.Dom

/-- The axioms a declaration may rest on and still count as machine
checked. -/
def standardAxioms : List Name :=
  [``propext, ``Classical.choice, ``Quot.sound, ``Lean.ofReduceBool, ``Lean.trustCompiler]

/-- Whether a module is in scope: any module of this project whose name
starts with the requested prefix (`RequestProject` by default). -/
def inScope (pre : Name) (m : Name) : Bool := (`RequestProject).isPrefixOf m && pre.isPrefixOf m

/-- The kind of a constant, as the catalog names it. -/
def constKind : ConstantInfo → Option String
  | .thmInfo _ => some "theorem"
  | .defnInfo _ => some "def"
  | .inductInfo _ => some "inductive"
  | .opaqueInfo _ => some "opaque"
  | .axiomInfo _ => some "axiom"
  | _ => none

/-- The source path of a module. -/
def modulePath (m : Name) : String :=
  m.components.foldl (fun acc c => if acc.isEmpty then c.toString else acc ++ "/" ++ c.toString) ""
    ++ ".lean"

/-- One scanned declaration. -/
structure Scanned where
  name : String
  kind : String
  file : String
  line : Nat
  statement : String
  sorried : Bool
  axiomsOk : Bool
  deps : List String

/-- Turn a scanned declaration into a catalog entry. -/
def Scanned.toDecl (s : Scanned) : Decl :=
  { name := s.name.toList, kind := s.kind.toList, file := s.file.toList, line := s.line,
    statement := s.statement.toList, sorried := s.sorried, axiomsOk := s.axiomsOk,
    deps := s.deps.map String.toList }

/-- Collect every declaration of the corpus. -/
def scanCorpus (pre : Name) : CoreM (Array Scanned) := do
  let env ← getEnv
  let names : Array Name := env.constants.fold (init := #[]) fun acc n _ =>
    match env.getModuleIdxFor? n with
    | some idx =>
        if inScope pre env.header.moduleNames[idx.toNat]! && !n.isInternal
            && !n.isImplementationDetail then acc.push n else acc
    | none => acc
  let nameSet : Std.HashSet Name := names.foldl (fun s n => s.insert n) {}
  let mut out : Array Scanned := #[]
  for n in names do
    let some info := env.find? n | continue
    let some kind := constKind info | continue
    let idx := env.getModuleIdxFor? n |>.get!
    let mdl := env.header.moduleNames[idx.toNat]!
    let line ← do
      match ← findDeclarationRanges? n with
      | some r => pure r.range.pos.line
      | none => pure 0
    let stmt ← Meta.MetaM.run' do
      let fmt ← Meta.ppExpr info.type
      pure (fmt.pretty 100 |>.replace "\n" " ")
    let axs ← collectAxioms n
    let sorried := axs.contains ``sorryAx
    let axiomsOk := axs.all (fun a => standardAxioms.contains a)
    let used := (info.type.getUsedConstants ++ (info.value?.map Expr.getUsedConstants).getD #[])
    let deps := used.foldl (fun (acc : Array Name) c =>
        if c != n && nameSet.contains c && !acc.contains c then acc.push c else acc) #[]
    out := out.push
      { name := n.toString, kind, file := modulePath mdl, line,
        statement := stmt, sorried, axiomsOk,
        deps := (deps.toList.map Name.toString) }
  pure out

/-- The scan of the corpus, written as one canonical value. -/
unsafe def main (args : List String) : IO Unit := do
  let outfile : System.FilePath := (args.head?.getD "domain/corpus-scan.kant")
  let modulePrefix : Name :=
    match args.drop 1 with
    | p :: _ => p.toName
    | [] => `RequestProject
  initSearchPath (← findSysroot)
  IO.println s!"loading the compiled corpus (modules under {modulePrefix}) …"
  (← IO.getStdout).flush
  let env ← importModules
    #[{ module := `RequestProject.Kant }, { module := `RequestProject.Wasm },
       { module := `RequestProject.Main }] {} (trustLevel := 1024)
  let (scanned, _) ← (scanCorpus modulePrefix).toIO
    { fileName := "<emitdomain>", fileMap := default } { env }
  IO.println s!"scanned {scanned.size} declarations; statement characters \
{scanned.foldl (fun a s => a + s.statement.length) 0}, dependency edges \
{scanned.foldl (fun a s => a + s.deps.length) 0}"
  (← IO.getStdout).flush
  let decls := scanned.toList.map Scanned.toDecl
  let names := decls.map Decl.name
  let nameSet : Std.HashSet String := names.foldl (fun s n => s.insert (String.ofList n)) {}
  -- keep the corpus closed: a dependency outside the scan is not a domain object
  let closed := decls.map fun d =>
    { d with deps := d.deps.filter (fun n => nameSet.contains (String.ofList n)) }
  if let some dir := outfile.parent then IO.FS.createDirAll dir
  IO.FS.writeFile outfile (String.ofList (canonEnc (scanVal closed)))
  IO.println s!"wrote {outfile} ({closed.length} declarations)"
