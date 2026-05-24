{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "actix-codec
lines";
  version = "0.5.2
2
1
0.3.7
0.3.7
2.3
0.2
1.23.1
0.7
0.1.30";
  src = ././vendor/actix-codec-0.5.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "actix-codec
lines";
  #   license = lib.licenses.mit;
  # };
}
