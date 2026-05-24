{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "wasm-bindgen-futures
wasm_bindgen_futures";
  version = "0.4.68
=0.3.95
=0.2.118
0.3
2";
  src = ././vendor/wasm-bindgen-futures-0.4.68;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "wasm-bindgen-futures
wasm_bindgen_futures";
  #   license = lib.licenses.mit;
  # };
}
