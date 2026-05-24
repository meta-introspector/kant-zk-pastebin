{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "wasmparser
wasmparser
simple
big-module
benchmark";
  version = "0.244.0
2.4.1
0.15.2
2.7.0
1.0.0
1.0.166
1.0.58
0.5.1
0.11
0.4.17
1.13.0
1.3";
  src = ././vendor/wasmparser-0.244.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "wasmparser
wasmparser
simple
big-module
benchmark";
  #   license = lib.licenses.mit;
  # };
}
