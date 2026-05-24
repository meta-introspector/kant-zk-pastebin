{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "convert_case
convert_case
macros
string_types
convert";
  version = "0.10.0
1.9.0
0.5";
  src = ././vendor/convert_case-0.10.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "convert_case
convert_case
macros
string_types
convert";
  #   license = lib.licenses.mit;
  # };
}
