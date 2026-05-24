{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "regex-syntax
regex_syntax
bench";
  version = "0.8.10
1.3.0";
  src = ././vendor/regex-syntax-0.8.10;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "regex-syntax
regex_syntax
bench";
  #   license = lib.licenses.mit;
  # };
}
