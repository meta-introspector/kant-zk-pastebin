{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "either
either";
  version = "1.15.0
1.0.95
1.0.0";
  src = ././vendor/either-1.15.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "either
either";
  #   license = lib.licenses.mit;
  # };
}
