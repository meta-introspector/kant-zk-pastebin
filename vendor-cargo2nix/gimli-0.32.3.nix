{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "gimli
gimli";
  version = "0.32.3
1.0.0
1.0.0
0.3.0
2.0.0
1.1.0
0.1.3";
  src = ././vendor/gimli-0.32.3;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "gimli
gimli";
  #   license = lib.licenses.mit;
  # };
}
