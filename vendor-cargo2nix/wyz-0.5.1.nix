{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "wyz";
  version = "0.5.1
1
1
0.3";
  src = ././vendor/wyz-0.5.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "wyz";
  #   license = lib.licenses.mit;
  # };
}
