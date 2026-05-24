{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "actix-web-codegen";
  version = "4.3.0
0.5
1
1
2
0.2.4
2.2
0.1
3
4
0.3.17
1
1";
  src = ././vendor/actix-web-codegen-4.3.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "actix-web-codegen";
  #   license = lib.licenses.mit;
  # };
}
