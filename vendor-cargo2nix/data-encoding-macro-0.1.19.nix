{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "data-encoding-macro
data_encoding_macro";
  version = "0.1.19
2.10.0
0.1.17";
  src = ././vendor/data-encoding-macro-0.1.19;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "data-encoding-macro
data_encoding_macro";
  #   license = lib.licenses.mit;
  # };
}
