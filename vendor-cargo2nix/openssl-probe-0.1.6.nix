{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "openssl-probe
openssl_probe
probe";
  version = "0.1.6";
  src = ././vendor/openssl-probe-0.1.6;
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
