{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "wit-bindgen-core
wit_bindgen_core";
  version = "0.51.0
1.0.72
4.3.19
0.5
1.0.218
0.244.0";
  src = ././vendor/wit-bindgen-core-0.51.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "wit-bindgen-core
wit_bindgen_core";
  #   license = lib.licenses.mit;
  # };
}
