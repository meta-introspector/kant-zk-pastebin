{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "prost
prost
varint";
  version = "0.14.3
1
0.14.3
0.7
1
0.9";
  src = ././vendor/prost-0.14.3;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "prost
prost
varint";
  #   license = lib.licenses.mit;
  # };
}
