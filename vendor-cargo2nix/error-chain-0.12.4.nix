{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "error-chain";
  version = "0.12.4
0.3.3
0.9";
  src = ././vendor/error-chain-0.12.4;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "error-chain";
  #   license = lib.licenses.mit;
  # };
}
