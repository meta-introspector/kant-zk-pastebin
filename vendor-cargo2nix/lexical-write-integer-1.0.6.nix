{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "lexical-write-integer
lexical_write_integer
api_tests
decimal_tests
digit_count_tests
options_tests
radix_tests
util";
  version = "1.0.6
1.0.7";
  src = ././vendor/lexical-write-integer-1.0.6;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "lexical-write-integer
lexical_write_integer
api_tests
decimal_tests
digit_count_tests
options_tests
radix_tests
util";
  #   license = lib.licenses.mit;
  # };
}
