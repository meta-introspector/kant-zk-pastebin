{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "heck";
  version = "0.5.0";
  src = ././vendor/heck-0.5.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "heck";
  #   license = lib.licenses.mit;
  # };
}
