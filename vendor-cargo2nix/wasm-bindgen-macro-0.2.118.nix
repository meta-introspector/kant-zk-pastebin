{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "wasm-bindgen-macro
wasm_bindgen_macro";
  version = "0.2.118
1.0
=0.2.118
1.0";
  src = ././vendor/wasm-bindgen-macro-0.2.118;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "wasm-bindgen-macro
wasm_bindgen_macro";
  #   license = lib.licenses.mit;
  # };
}
