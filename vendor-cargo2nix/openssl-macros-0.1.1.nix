{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "openssl-macros";
  version = "0.1.1
1
1
2";
  src = ././vendor/openssl-macros-0.1.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "openssl-macros";
  #   license = lib.licenses.mit;
  # };
}
