{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "blake3
blake3
bench";
  version = "1.8.4
0.3.5
0.7.4
1.0.0
0.4.2
0.11.2
0.9
1.12.1
1.0
1
0.10.0
0.2.2
0.4.2
0.13.0
0.6.0
0.10.0
1.0.107
3.8.0
1.1.12
0.3.0";
  src = ././vendor/blake3-1.8.4;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "blake3
blake3
bench";
  #   license = lib.licenses.mit;
  # };
}
