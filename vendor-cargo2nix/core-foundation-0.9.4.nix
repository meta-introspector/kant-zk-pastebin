{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "core-foundation";
  version = "0.9.4
0.4
0.8.6
0.2
0.5";
  src = ././vendor/core-foundation-0.9.4;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "core-foundation";
  #   license = lib.licenses.mit;
  # };
}
