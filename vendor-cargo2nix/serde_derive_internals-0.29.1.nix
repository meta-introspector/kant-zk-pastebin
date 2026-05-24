{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "serde_derive_internals
serde_derive_internals";
  version = "0.29.1
1.0.74
1.0.35
2.0.46";
  src = ././vendor/serde_derive_internals-0.29.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "serde_derive_internals
serde_derive_internals";
  #   license = lib.licenses.mit;
  # };
}
