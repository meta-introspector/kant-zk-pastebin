{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "sha3";
  version = "0.10.8
0.10.4
0.1.4
0.10.4
0.2.2";
  src = ././vendor/sha3-0.10.8;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "sha3";
  #   license = lib.licenses.mit;
  # };
}
