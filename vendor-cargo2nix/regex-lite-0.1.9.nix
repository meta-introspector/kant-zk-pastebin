{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "regex-lite
regex_lite
integration";
  version = "0.1.9
1.0.69
0.1.0";
  src = ././vendor/regex-lite-0.1.9;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "regex-lite
regex_lite
integration";
  #   license = lib.licenses.mit;
  # };
}
