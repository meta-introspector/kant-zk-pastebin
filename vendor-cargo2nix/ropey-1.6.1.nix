{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "ropey
create
insert
hash
remove
queries
iterators";
  version = "1.6.1
1.0.0
0.4
0.3
1
0.2
1.0
0.8
1.3";
  src = ././vendor/ropey-1.6.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "ropey
create
insert
hash
remove
queries
iterators";
  #   license = lib.licenses.mit;
  # };
}
