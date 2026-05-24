{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "miniz_oxide
miniz_oxide";
  version = "0.8.9
2.0
1.0.0
1.0.0
1.0
0.3.3";
  src = ././vendor/miniz_oxide-0.8.9;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "miniz_oxide
miniz_oxide";
  #   license = lib.licenses.mit;
  # };
}
