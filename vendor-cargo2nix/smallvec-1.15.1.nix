{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "smallvec
smallvec
debugger_visualizer
macro
bench";
  version = "1.15.1
1
2
0.1
1
0.0.4
1.0.1
0.1.0
0.1.0";
  src = ././vendor/smallvec-1.15.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "smallvec
smallvec
debugger_visualizer
macro
bench";
  #   license = lib.licenses.mit;
  # };
}
