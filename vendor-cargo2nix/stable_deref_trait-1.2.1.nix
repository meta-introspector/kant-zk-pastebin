{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "stable_deref_trait
stable_deref_trait";
  version = "1.2.1";
  src = ././vendor/stable_deref_trait-1.2.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "stable_deref_trait
stable_deref_trait";
  #   license = lib.licenses.mit;
  # };
}
