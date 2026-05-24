{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "wasm-encoder
wasm_encoder";
  version = "0.244.0
0.1.0
0.244.0
1.0.58
3.2.0
0.244.0";
  src = ././vendor/wasm-encoder-0.244.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "wasm-encoder
wasm_encoder";
  #   license = lib.licenses.mit;
  # };
}
