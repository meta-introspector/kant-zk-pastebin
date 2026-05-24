{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "base-x
base";
  version = "0.2.11
0.1
0.12
0.8";
  src = ././vendor/base-x-0.2.11;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "base-x
base";
  #   license = lib.licenses.mit;
  # };
}
