{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "sha3
sha3
mod
serialization
mod";
  version = "0.11.0
0.11
0.2
0.11
1";
  src = ././vendor/sha3-0.11.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "sha3
sha3
mod
serialization
mod";
  #   license = lib.licenses.mit;
  # };
}
