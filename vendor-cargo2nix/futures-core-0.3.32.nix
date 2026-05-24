{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "futures-core
futures_core";
  version = "0.3.32
1.3";
  src = ././vendor/futures-core-0.3.32;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "futures-core
futures_core";
  #   license = lib.licenses.mit;
  # };
}
