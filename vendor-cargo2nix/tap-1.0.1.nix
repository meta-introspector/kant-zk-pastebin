{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "tap";
  version = "1.0.1";
  src = ././vendor/tap-1.0.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "tap";
  #   license = lib.licenses.mit;
  # };
}
