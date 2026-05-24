{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "hybrid-array
hybrid_array
ctutils
mod
subtle";
  version = "0.4.10
1
1
0.4
1
2
1.17
0.8
1.8
1";
  src = ././vendor/hybrid-array-0.4.10;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "hybrid-array
hybrid_array
ctutils
mod
subtle";
  #   license = lib.licenses.mit;
  # };
}
