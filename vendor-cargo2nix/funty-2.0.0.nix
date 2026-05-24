{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "funty";
  version = "2.0.0
1";
  src = ././vendor/funty-2.0.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "funty";
  #   license = lib.licenses.mit;
  # };
}
