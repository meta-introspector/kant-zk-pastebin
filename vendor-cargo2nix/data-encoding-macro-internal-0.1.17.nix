{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "data-encoding-macro-internal
data_encoding_macro_internal";
  version = "0.1.17
2.10.0
>= 1, < 3";
  src = ././vendor/data-encoding-macro-internal-0.1.17;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "data-encoding-macro-internal
data_encoding_macro_internal";
  #   license = lib.licenses.mit;
  # };
}
