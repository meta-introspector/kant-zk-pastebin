{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "toml_write
toml_write";
  version = "0.1.2
1.6.0
0.6.0
0.5.10";
  src = ././vendor/toml_write-0.1.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "toml_write
toml_write";
  #   license = lib.licenses.mit;
  # };
}
