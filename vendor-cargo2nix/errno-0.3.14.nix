{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "errno
errno";
  version = "0.3.14
0.2
0.2
0.2
>=0.52, <0.62";
  src = ././vendor/errno-0.3.14;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "errno
errno";
  #   license = lib.licenses.mit;
  # };
}
