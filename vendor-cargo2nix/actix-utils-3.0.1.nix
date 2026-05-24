{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "actix-utils
actix_utils";
  version = "3.0.1
0.1
0.2";
  src = ././vendor/actix-utils-3.0.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "actix-utils
actix_utils";
  #   license = lib.licenses.mit;
  # };
}
