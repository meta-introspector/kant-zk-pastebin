{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "cc
cc";
  version = "1.2.60
0.1.9
0.1.30
1.3.0
3
0.2.62";
  src = ././vendor/cc-1.2.60;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "cc
cc";
  #   license = lib.licenses.mit;
  # };
}
