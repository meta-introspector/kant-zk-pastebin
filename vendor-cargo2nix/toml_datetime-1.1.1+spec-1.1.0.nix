{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "toml_datetime
toml_datetime";
  version = "1.1.1+spec-1.1.0
1.0.228
1.1.0";
  src = ././vendor/toml_datetime-1.1.1+spec-1.1.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "toml_datetime
toml_datetime";
  #   license = lib.licenses.mit;
  # };
}
