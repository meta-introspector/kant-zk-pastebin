{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "leb128fmt";
  version = "0.1.0";
  src = ././vendor/leb128fmt-0.1.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "leb128fmt";
  #   license = lib.licenses.mit;
  # };
}
