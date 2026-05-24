{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "openssl-sys
openssl_sys";
  version = "0.9.113
0.13
0.39
0.1.0
0.2
0.72.0
1.0.61
300.2.0
0.3.9
0.2.8";
  src = ././vendor/openssl-sys-0.9.113;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "openssl-sys
openssl_sys";
  #   license = lib.licenses.mit;
  # };
}
