{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "crypto-common
crypto_common";
  version = "0.2.1
0.4
0.4.7
0.10";
  src = ././vendor/crypto-common-0.2.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "crypto-common
crypto_common";
  #   license = lib.licenses.mit;
  # };
}
