{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "proc-macro-crate
proc_macro_crate
workspace_deps";
  version = "3.5.0
0.25.0
1.0.94
1.0.39
2.0.99";
  src = ././vendor/proc-macro-crate-3.5.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "proc-macro-crate
proc_macro_crate
workspace_deps";
  #   license = lib.licenses.mit;
  # };
}
