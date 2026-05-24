{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "actix-router
actix_router
quoter
router";
  version = "0.5.4
>=0.1.5, <2
1
0.2.7
1.5
0.1
1
0.1.30
0.5
0.2.7
2.1
1";
  src = ././vendor/actix-router-0.5.4;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "actix-router
actix_router
quoter
router";
  #   license = lib.licenses.mit;
  # };
}
