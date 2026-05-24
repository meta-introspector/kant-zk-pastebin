{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "chrono
chrono
dateutils
wasm
win_bindings";
  version = "0.4.39
1.0.0
0.2
0.8
0.7.43
1.0.99
1.3.0
1
1
0.3
0.2
0.3
0.1.1
0.1.45
0.52
0.58";
  src = ././vendor/chrono-0.4.39;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "chrono
chrono
dateutils
wasm
win_bindings";
  #   license = lib.licenses.mit;
  # };
}
