{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "serde
serde";
  version = "1.0.228
=1.0.228
1";
  src = ././vendor/serde-1.0.228;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "serde
serde";
  #   license = lib.licenses.mit;
  # };
}
