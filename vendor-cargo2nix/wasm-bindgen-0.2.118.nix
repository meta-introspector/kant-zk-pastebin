{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "wasm-bindgen
wasm_bindgen";
  version = "0.2.118
1.0.0
1.12
1.0
1.0
=0.2.118
=0.2.118
1
1.0.6
1
1.0";
  src = ././vendor/wasm-bindgen-0.2.118;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "wasm-bindgen
wasm_bindgen";
  #   license = lib.licenses.mit;
  # };
}
