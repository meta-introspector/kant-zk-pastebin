{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "hashbrown
hashbrown
equivalent_trait
hasher
rayon
serde
set
bench
insert_unique_unchecked
set_ops";
  version = "0.15.5
1.0.0
0.2.9
1.0.0
1.0
0.1.2
1.2
1.0.25
3.13.0
0.3.1
1.0.7
1.4
0.9.0
1.2
1.0";
  src = ././vendor/hashbrown-0.15.5;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "hashbrown
hashbrown
equivalent_trait
hasher
rayon
serde
set
bench
insert_unique_unchecked
set_ops";
  #   license = lib.licenses.mit;
  # };
}
