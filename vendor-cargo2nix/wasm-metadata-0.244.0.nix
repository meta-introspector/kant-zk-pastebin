{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "wasm-metadata
wasm_metadata
component
module";
  version = "0.244.0
1.0.58
0.8.0
4.0.0
1.1.0
2.7.0
1.0.166
1.0.166
1
0.10.1
2.0.0
0.244.0
0.244.0";
  src = ././vendor/wasm-metadata-0.244.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "wasm-metadata
wasm_metadata
component
module";
  #   license = lib.licenses.mit;
  # };
}
