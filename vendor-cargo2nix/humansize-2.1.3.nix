{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "humansize";
  version = "2.1.3
0.2.5";
  src = ././vendor/humansize-2.1.3;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "humansize";
  #   license = lib.licenses.mit;
  # };
}
