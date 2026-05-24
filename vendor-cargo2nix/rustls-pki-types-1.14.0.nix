{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "rustls-pki-types
rustls_pki_types";
  version = "1.14.0
1
1
=0.1.9";
  src = ././vendor/rustls-pki-types-1.14.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "rustls-pki-types
rustls_pki_types";
  #   license = lib.licenses.mit;
  # };
}
