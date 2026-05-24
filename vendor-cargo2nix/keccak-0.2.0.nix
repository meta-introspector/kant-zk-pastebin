{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "keccak
keccak
parallel
xkcp
mod";
  version = "0.2.0
1
0.4
0.3";
  src = ././vendor/keccak-0.2.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "keccak
keccak
parallel
xkcp
mod";
  #   license = lib.licenses.mit;
  # };
}
