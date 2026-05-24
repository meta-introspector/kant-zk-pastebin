{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "serde_spanned
serde_spanned";
  version = "0.6.9
1.0.145
1
0.1
1";
  src = ././vendor/serde_spanned-0.6.9;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "serde_spanned
serde_spanned";
  #   license = lib.licenses.mit;
  # };
}
