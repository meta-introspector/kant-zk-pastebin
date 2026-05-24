{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "crypto-common
crypto_common";
  version = "0.1.7
=0.14.7
0.6
1.14";
  src = ././vendor/crypto-common-0.1.7;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "crypto-common
crypto_common";
  #   license = lib.licenses.mit;
  # };
}
