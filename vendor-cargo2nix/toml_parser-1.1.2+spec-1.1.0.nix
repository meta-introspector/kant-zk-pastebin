{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "toml_parser
toml_parser";
  version = "1.1.2+spec-1.1.0
1.0.0
1.0.14
1.0.0
1.0.0
1.1.0";
  src = ././vendor/toml_parser-1.1.2+spec-1.1.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "toml_parser
toml_parser";
  #   license = lib.licenses.mit;
  # };
}
