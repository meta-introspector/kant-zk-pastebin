{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "encoding_rs
encoding_rs";
  version = "0.8.35
0.1.0
1.0
1.0
1.0
1.0
1.0";
  src = ././vendor/encoding_rs-0.8.35;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "encoding_rs
encoding_rs";
  #   license = lib.licenses.mit;
  # };
}
