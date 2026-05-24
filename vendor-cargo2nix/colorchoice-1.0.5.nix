{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "colorchoice
colorchoice";
  version = "1.0.5";
  src = ././vendor/colorchoice-1.0.5;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "colorchoice
colorchoice";
  #   license = lib.licenses.mit;
  # };
}
