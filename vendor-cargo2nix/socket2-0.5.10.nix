{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "socket2
socket2";
  version = "0.5.10
0.2.171
0.52";
  src = ././vendor/socket2-0.5.10;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "socket2
socket2";
  #   license = lib.licenses.mit;
  # };
}
