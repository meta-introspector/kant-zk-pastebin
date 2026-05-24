{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "icu_collections
icu_collections
char16trie
cpt
codepointtrie
iai_cpt
inv_list";
  version = "2.2.0
0.2.0
0.2.3
0.1.3
1.0.220
1.0.2
0.8.2
0.1.6
0.11.6
0.1.1
1.0.3
1.0.220
1.0.45
0.8.0
0.5.0";
  src = ././vendor/icu_collections-2.2.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "icu_collections
icu_collections
char16trie
cpt
codepointtrie
iai_cpt
inv_list";
  #   license = lib.licenses.mit;
  # };
}
