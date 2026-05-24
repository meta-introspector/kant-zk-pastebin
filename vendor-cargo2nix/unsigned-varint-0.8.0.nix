{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "unsigned-varint
benchmark";
  version = "0.8.0
0.7
1
0.3.4
0.3.4
7
0.7
0.3
0.3.4
0.4
1";
  src = ././vendor/unsigned-varint-0.8.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "unsigned-varint
benchmark";
  #   license = lib.licenses.mit;
  # };
}
