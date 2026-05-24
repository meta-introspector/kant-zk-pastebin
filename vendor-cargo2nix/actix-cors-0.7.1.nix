{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "actix-cors
actix_cors
cors
tests";
  version = "0.7.1
3
4
2
0.3.17
0.4
1
1
4
0.11
1.4";
  src = ././vendor/actix-cors-0.7.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "actix-cors
actix_cors
cors
tests";
  #   license = lib.licenses.mit;
  # };
}
