{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "wit-bindgen
wit_bindgen";
  version = "0.51.0
1.0
2.3.3
1.0
0.3.30
0.51.0";
  src = ././vendor/wit-bindgen-0.51.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "wit-bindgen
wit_bindgen";
  #   license = lib.licenses.mit;
  # };
}
