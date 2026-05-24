{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "litemap
litemap
language_names_hash_map
language_names_lite_map
litemap_bincode
litemap_postcard
rkyv
serde
store
litemap";
  version = "0.8.2
0.2.0
1.0.220
0.8.2
1.3.1
1.0.3
0.9
0.7
1.0.220
1.0.45
0.5.0";
  src = ././vendor/litemap-0.8.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "litemap
litemap
language_names_hash_map
language_names_lite_map
litemap_bincode
litemap_postcard
rkyv
serde
store
litemap";
  #   license = lib.licenses.mit;
  # };
}
