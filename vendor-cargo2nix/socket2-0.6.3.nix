{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "socket2
socket2";
  version = "0.6.3
0.2.172
>=0.60, <0.62";
  src = ././vendor/socket2-0.6.3;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "socket2
socket2";
  #   license = lib.licenses.mit;
  # };
}
