{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "lexical-util
lexical_util
algorithm_tests
ascii_tests
bf16_tests
digit_tests
f16_tests
feature_format_tests
format_builder_tests
format_flags_tests
iterator_tests
not_feature_format_tests
num_tests
skip_tests";
  version = "1.0.7
0.1.0";
  src = ././vendor/lexical-util-1.0.7;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "lexical-util
lexical_util
algorithm_tests
ascii_tests
bf16_tests
digit_tests
f16_tests
feature_format_tests
format_builder_tests
format_flags_tests
iterator_tests
not_feature_format_tests
num_tests
skip_tests";
  #   license = lib.licenses.mit;
  # };
}
