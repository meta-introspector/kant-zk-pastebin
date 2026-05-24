{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "fnv
fnv";
  version = "1.0.7";
  src = ././vendor/fnv-1.0.7;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "fnv
fnv";
  #   license = lib.licenses.mit;
  # };
}
