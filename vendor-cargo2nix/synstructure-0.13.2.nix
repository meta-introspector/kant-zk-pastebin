{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "synstructure
synstructure";
  version = "0.13.2
1.0.60
1
2
0.1";
  src = ././vendor/synstructure-0.13.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "synstructure
synstructure";
  #   license = lib.licenses.mit;
  # };
}
