{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "keccak
keccak
mod";
  version = "0.1.6
0.2";
  src = ././vendor/keccak-0.1.6;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "keccak
keccak
mod";
  #   license = lib.licenses.mit;
  # };
}
