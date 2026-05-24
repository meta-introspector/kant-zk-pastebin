{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "darling_macro
darling_macro";
  version = "0.20.11
=0.20.11
1.0.18
2.0.15";
  src = ././vendor/darling_macro-0.20.11;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "darling_macro
darling_macro";
  #   license = lib.licenses.mit;
  # };
}
