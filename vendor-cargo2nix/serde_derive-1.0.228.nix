{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "serde_derive
serde_derive";
  version = "1.0.228
1.0.74
1.0.35
2.0.81
1";
  src = ././vendor/serde_derive-1.0.228;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "serde_derive
serde_derive";
  #   license = lib.licenses.mit;
  # };
}
