{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "hashbrown
hashbrown
equivalent_trait
hasher
hasher_unwind
rayon
serde
set
bench";
  version = "0.17.0
1.0.0
0.2.9
1.0.0
1.0
0.2.0
1.9.0
1.0.221
3.13.0
0.7
1.0.7
0.9.0
1.2
1.0
1.0.220
0.2.155";
  src = ././vendor/hashbrown-0.17.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "hashbrown
hashbrown
equivalent_trait
hasher
hasher_unwind
rayon
serde
set
bench";
  #   license = lib.licenses.mit;
  # };
}
