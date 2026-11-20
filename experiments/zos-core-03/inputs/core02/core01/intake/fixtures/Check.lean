/-
# JobVerifier.Check — TEST_ONLY PR #25 remediation checker

Implements the CHECK-sandbox decision from the independent audit's
remediation design (`STEP25_PR25_REMEDIATION_DESIGN.md` §4.3):

  * decide from the elaborated ENVIRONMENT, never from lexer output
  * `env.find? decl` must be a `thmInfo` defined in the submission module
  * `c.type` must be structurally equal to the reference `__expected : Prop`
  * `Lean.collectAxioms` over the environment (closes sorry/private/raw-string
    lexer bypasses as a class)
  * any axiom DECLARED in the submission module fails (AXIOM_DECLARED)

Exit codes: 0 = accepted, 1 = rejected (reason on stdout), 2 = checker error.
This is TEST_ONLY: no sandbox, no signatures, no kernel replay yet.
See README.md for what is and is not covered.
-/
import Lean

open Lean

inductive Reason where
  | ok | targetMissing | targetNotTheorem | statementMismatch
  | sorryAxiom | axiomNotAllowed | axiomDeclared
  | importFailed | checkerError | referenceNotInModule
  deriving Inhabited, Repr

def Reason.code : Reason → String
  | .ok => "OK"
  | .targetMissing => "TARGET_MISSING"
  | .targetNotTheorem => "TARGET_NOT_THEOREM"
  | .statementMismatch => "STATEMENT_MISMATCH"
  | .sorryAxiom => "SORRY"
  | .axiomNotAllowed => "AXIOM_NOT_ALLOWED"
  | .axiomDeclared => "AXIOM_DECLARED"
  | .importFailed => "IMPORT_FAILED"
  | .checkerError => "CHECKER_ERROR"
  | .referenceNotInModule => "REFERENCE_NOT_IN_MODULE"

structure Cfg where
  module : Name
  decl : Name
  refModule : Name
  expectedName : Name
  allowedAxioms : List Name

def verdict (r : Reason) (cfg : Cfg) (axioms : List Name := [])
    (declared : List Name := []) (extra : String := "") : IO Unit := do
  let _ := extra
  let result := Json.mkObj
    [ ("schema", toJson ("zos.verify.v1-testonly" : String))
    , ("jobModule", toJson (toString cfg.module))
    , ("decl", toJson (toString cfg.decl))
    , ("reasonCode", toJson r.code)
    , ("axioms", toJson (axioms.map toString))
    , ("declaredAxiomsInSubmission", toJson (declared.map toString))
    ]
  IO.println result.compress

/-- All constants defined in `mod` whose ConstantInfo is an axiomInfo. -/
def declaredAxioms (env : Environment) (mod : Name) : List Name := Id.run do
  let some idx := env.getModuleIdx? mod | []
  let some md := env.header.moduleData[idx]? | []
  md.constNames.foldl (init := []) fun acc n =>
    match env.find? n with
    | some (.axiomInfo _) => n :: acc
    | _ => acc

/-- The full decision procedure. Exit 0 accepted / 1 rejected / 2 checker error. -/
def run (cfg : Cfg) : IO UInt32 := do
  initSearchPath (← findSysroot)
  let envOpt ←
    try
      let imported ←
        importModules
          #[{ module := cfg.refModule },
            { module := cfg.module }]
          (opts := {}) (trustLevel := 0)
      pure (some imported : Option Environment)
    catch _ =>
      verdict .importFailed cfg
      pure (none : Option Environment)
  let some env := envOpt
    | return 1
  let some expectedInfo := env.find? cfg.expectedName
    | do
        verdict .checkerError cfg (extra := ",\"detail\":\"reference __expected missing\"")
        return 2
  -- Validate reference declaration ownership.
  let some refIdx := env.getModuleIdx? cfg.refModule
    | do
        verdict .referenceNotInModule cfg
        return 1
  if env.getModuleIdxFor? cfg.expectedName != some refIdx then
    verdict .referenceNotInModule cfg
    return 1
  let some c := env.find? cfg.decl
    | do verdict .targetMissing cfg; return 1
  let .thmInfo thm := c
    | do verdict .targetNotTheorem cfg; return 1
  -- The declaration must be defined in the submission module, not imported.
  if env.getModuleIdxFor? cfg.decl != env.getModuleIdx? cfg.module then
    verdict .targetMissing cfg (extra := ",\"detail\":\"decl not defined in submission module\"")
    return 1
  -- Level parameters and type must match the reference structurally.
  if c.levelParams != expectedInfo.levelParams || thm.type != expectedInfo.type then
    verdict .statementMismatch cfg; return 1
  -- Axioms from the environment (no lexer involved).
  let axs ←
    (collectAxioms cfg.decl : CoreM (Array Name)).toIO'
      { fileName := "<jobverifier>", fileMap := default }
      { env := env }
  let axioms := axs.toList
  if axioms.contains `sorryAx then
    verdict .sorryAxiom cfg (axioms := axioms); return 1
  let bad := axioms.filter (· ∉ cfg.allowedAxioms)
  if !bad.isEmpty then
    verdict .axiomNotAllowed cfg (axioms := axioms); return 1
  -- The submission must not declare axioms of its own (defence in depth).
  let declared := declaredAxioms env cfg.module
  if !declared.isEmpty then
    verdict .axiomDeclared cfg (declared := declared); return 1
  verdict .ok cfg (axioms := axioms)
  return 0

def parseArgs : List String → Option Cfg
  | ["--module", m, "--decl", d, "--ref", r, "--expected", e] =>
    some { module := m.toName, decl := d.toName, refModule := r.toName,
           expectedName := e.toName,
           allowedAxioms := [`propext, `Classical.choice, `Quot.sound] }
  | _ => none

def main (args : List String) : IO UInt32 := do
  match parseArgs args with
  | some cfg => run cfg
  | none =>
    IO.eprintln "usage: jobverifier --module M --decl D --ref R --expected E"
    IO.eprintln "  LEAN_PATH must contain the pinned deps and the staged submission olean."
    return 2
