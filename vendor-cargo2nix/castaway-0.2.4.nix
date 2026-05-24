{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "castaway
castaway";
  version = "0.2.4
1
1";
  src = ././vendor/castaway-0.2.4;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "castaway
castaway";
  #   license = lib.licenses.mit;
  # };
}
