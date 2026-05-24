{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "openssl-probe
openssl_probe
probe";
  version = "0.2.1";
  src = ././vendor/openssl-probe-0.2.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "openssl-probe
openssl_probe
probe";
  #   license = lib.licenses.mit;
  # };
}
