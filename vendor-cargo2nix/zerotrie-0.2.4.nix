{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "zerotrie
zerotrie
first_weekday_for_region
asciitrie_test
builder_test
dense_test
derive_test
ignorecase_test
locale_aux_test
overview";
  version = "0.2.4
0.2.0
0.2.3
0.8.0
1.0.220
0.8.2
0.1.6
0.11.6
1.3.1
2.2.0
0.14.0
1.0.3
0.9
0.9
1.2.0
1.0.220
1.0.45
0.5.0";
  src = ././vendor/zerotrie-0.2.4;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "zerotrie
zerotrie
first_weekday_for_region
asciitrie_test
builder_test
dense_test
derive_test
ignorecase_test
locale_aux_test
overview";
  #   license = lib.licenses.mit;
  # };
}
