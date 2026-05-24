{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "toml_datetime
toml_datetime";
  version = "0.6.11
1.0.145
0.6.21";
  src = ././vendor/toml_datetime-0.6.11;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "toml_datetime
toml_datetime";
  #   license = lib.licenses.mit;
  # };
}
