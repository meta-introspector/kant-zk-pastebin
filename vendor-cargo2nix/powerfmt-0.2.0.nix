{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "powerfmt";
  version = "0.2.0
=0.1.0";
  src = ././vendor/powerfmt-0.2.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "powerfmt";
  #   license = lib.licenses.mit;
  # };
}
