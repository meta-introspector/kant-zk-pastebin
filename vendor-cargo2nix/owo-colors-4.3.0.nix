{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "owo-colors
owo_colors";
  version = "4.3.0
3.0.0
2.0";
  src = ././vendor/owo-colors-4.3.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "owo-colors
owo_colors";
  #   license = lib.licenses.mit;
  # };
}
