{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "wasm-bindgen-macro-support
wasm_bindgen_macro_support";
  version = "0.2.118
3.0.0
1.0
1.0
2.0
=0.2.118";
  src = ././vendor/wasm-bindgen-macro-support-0.2.118;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "wasm-bindgen-macro-support
wasm_bindgen_macro_support";
  #   license = lib.licenses.mit;
  # };
}
