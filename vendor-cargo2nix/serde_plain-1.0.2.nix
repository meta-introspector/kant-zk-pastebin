{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "serde_plain";
  version = "1.0.2
1.0.29
1.0.29";
  src = ././vendor/serde_plain-1.0.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "serde_plain";
  #   license = lib.licenses.mit;
  # };
}
