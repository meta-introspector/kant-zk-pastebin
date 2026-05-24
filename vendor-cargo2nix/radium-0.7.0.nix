{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "radium";
  version = "0.7.0
1";
  src = ././vendor/radium-0.7.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "radium";
  #   license = lib.licenses.mit;
  # };
}
