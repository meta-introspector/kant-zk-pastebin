{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "hex
hex";
  version = "0.4.3
1.0
0.3
0.5
0.6
2.1
1.0
1.0
0.9";
  src = ././vendor/hex-0.4.3;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "hex
hex";
  #   license = lib.licenses.mit;
  # };
}
