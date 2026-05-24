{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "actix-multipart-derive";
  version = "0.7.0
0.20
1
1
1
2
0.7
4
1
1";
  src = ././vendor/actix-multipart-derive-0.7.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "actix-multipart-derive";
  #   license = lib.licenses.mit;
  # };
}
