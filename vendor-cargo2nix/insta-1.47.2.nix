{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "insta
insta
test_advanced
test_basic
test_binary
test_comparator
test_glob
test_inline
test_redaction
test_settings
test_toml";
  version = "1.47.2
4.1
0.16
1.1.6
0.4.6
1.20.2
2.1.3
2.1.0
1.6.0
0.12.0
1.0.117
2.1.0
3
0.25.0
1
2.3.1
0.4.0
1.0.117
1.4.2";
  src = ././vendor/insta-1.47.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "insta
insta
test_advanced
test_basic
test_binary
test_comparator
test_glob
test_inline
test_redaction
test_settings
test_toml";
  #   license = lib.licenses.mit;
  # };
}
