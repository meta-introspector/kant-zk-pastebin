{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "base256emoji";
  version = "1.0.2
0.4.3
0.1.1";
  src = ././vendor/base256emoji-1.0.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "base256emoji";
  #   license = lib.licenses.mit;
  # };
}
