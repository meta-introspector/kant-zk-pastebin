{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "nonmax";
  version = "0.5.5
1.0
1.3";
  src = ././vendor/nonmax-0.5.5;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "nonmax";
  #   license = lib.licenses.mit;
  # };
}
