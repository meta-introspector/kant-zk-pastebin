{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "typenum
typenum
test";
  version = "1.19.0
1.0";
  src = ././vendor/typenum-1.19.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "typenum
typenum
test";
  #   license = lib.licenses.mit;
  # };
}
