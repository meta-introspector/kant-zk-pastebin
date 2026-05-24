{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "utoipa";
  version = "4.2.3
2
1.0
1.0
0.9
4.3.0
2";
  src = ././vendor/utoipa-4.2.3;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "utoipa";
  #   license = lib.licenses.mit;
  # };
}
