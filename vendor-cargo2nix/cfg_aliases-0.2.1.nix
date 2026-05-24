{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "cfg_aliases";
  version = "0.2.1";
  src = ././vendor/cfg_aliases-0.2.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "cfg_aliases";
  #   license = lib.licenses.mit;
  # };
}
