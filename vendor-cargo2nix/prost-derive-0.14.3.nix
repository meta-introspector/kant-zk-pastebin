{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "prost-derive
prost_derive";
  version = "0.14.3
1.0.1
>=0.10.1, <=0.14
1.0.60
1
2";
  src = ././vendor/prost-derive-0.14.3;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "prost-derive
prost_derive";
  #   license = lib.licenses.mit;
  # };
}
