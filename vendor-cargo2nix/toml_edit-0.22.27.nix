{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "toml_edit
toml_edit
visit";
  version = "0.22.27
2.3.0
2.0.0
1.0.145
0.6.9
0.6.11
0.1.2
0.7.10
1.5.0
1.0.199
1.0.116
0.6.0
2.3.0
1.3.2
2.5.0";
  src = ././vendor/toml_edit-0.22.27;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "toml_edit
toml_edit
visit";
  #   license = lib.licenses.mit;
  # };
}
