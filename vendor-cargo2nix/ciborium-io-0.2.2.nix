{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "ciborium-io";
  version = "0.2.2";
  src = ././vendor/ciborium-io-0.2.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "ciborium-io";
  #   license = lib.licenses.mit;
  # };
}
