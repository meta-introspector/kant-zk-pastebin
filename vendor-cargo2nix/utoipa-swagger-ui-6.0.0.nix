{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "utoipa-swagger-ui";
  version = "6.0.0
4
0.7
2.0
0.5
8
1.0
1.0
4
2.2
1.7
0.6";
  src = ././vendor/utoipa-swagger-ui-6.0.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "utoipa-swagger-ui";
  #   license = lib.licenses.mit;
  # };
}
