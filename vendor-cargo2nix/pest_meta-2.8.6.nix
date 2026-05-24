{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "pest_meta
pest_meta";
  version = "2.8.6
2.8.6
0.81.0
0.10";
  src = ././vendor/pest_meta-2.8.6;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "pest_meta
pest_meta";
  #   license = lib.licenses.mit;
  # };
}
