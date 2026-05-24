{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "strsim";
  version = "0.11.1";
  src = ././vendor/strsim-0.11.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "strsim";
  #   license = lib.licenses.mit;
  # };
}
