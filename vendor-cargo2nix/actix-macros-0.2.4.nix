{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "actix-macros";
  version = "0.2.4
1
2";
  src = ././vendor/actix-macros-0.2.4;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "actix-macros";
  #   license = lib.licenses.mit;
  # };
}
