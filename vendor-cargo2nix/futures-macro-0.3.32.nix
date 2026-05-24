{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "futures-macro
futures_macro";
  version = "0.3.32
1.0.60
1.0
2.0.52";
  src = ././vendor/futures-macro-0.3.32;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "futures-macro
futures_macro";
  #   license = lib.licenses.mit;
  # };
}
