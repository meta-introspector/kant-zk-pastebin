{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "arrayvec
arrayvec
borsh
serde
tests
arraystring
extend";
  version = "0.7.6
1.2.0
1.0
1.4
0.1.4
0.1
1.0";
  src = ././vendor/arrayvec-0.7.6;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "arrayvec
arrayvec
borsh
serde
tests
arraystring
extend";
  #   license = lib.licenses.mit;
  # };
}
