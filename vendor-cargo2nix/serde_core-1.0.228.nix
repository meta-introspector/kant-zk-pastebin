{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "serde_core
serde_core";
  version = "1.0.228
1
1
=1.0.228";
  src = ././vendor/serde_core-1.0.228;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "serde_core
serde_core";
  #   license = lib.licenses.mit;
  # };
}
