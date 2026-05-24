{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "multihash
multihash
identity";
  version = "0.19.4
1.1.0
0.8.1
3.0.0
1.0.3
0.10
1.0.116
0.8.0
0.4.2
1.0.58
1.0.160";
  src = ././vendor/multihash-0.19.4;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "multihash
multihash
identity";
  #   license = lib.licenses.mit;
  # };
}
