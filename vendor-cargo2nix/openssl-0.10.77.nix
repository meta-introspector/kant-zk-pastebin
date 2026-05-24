{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "openssl
openssl
mk_certs";
  version = "0.10.77
2.2.1
1.0
0.9.113
0.3.1
0.2
1.5.2
0.1.1
0.4";
  src = ././vendor/openssl-0.10.77;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "openssl
openssl
mk_certs";
  #   license = lib.licenses.mit;
  # };
}
