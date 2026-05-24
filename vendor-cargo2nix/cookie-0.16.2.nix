{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "cookie";
  version = "0.16.2
0.10.0
0.20
0.12.0
0.12.0
2.0
0.8
0.10.0
2.3
0.3
0.9.4";
  src = ././vendor/cookie-0.16.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "cookie";
  #   license = lib.licenses.mit;
  # };
}
