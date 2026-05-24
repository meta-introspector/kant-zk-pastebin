{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "wasm-bindgen-shared
wasm_bindgen_shared";
  version = "0.2.118
1.0.5";
  src = ././vendor/wasm-bindgen-shared-0.2.118;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "wasm-bindgen-shared
wasm_bindgen_shared";
  #   license = lib.licenses.mit;
  # };
}
