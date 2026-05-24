{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "cast";
  version = "0.3.0
1.0.3";
  src = ././vendor/cast-0.3.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "cast";
  #   license = lib.licenses.mit;
  # };
}
