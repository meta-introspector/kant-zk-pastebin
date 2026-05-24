{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "quickcheck
quickcheck
btree_set_range
out_of_bounds
reverse
reverse_single
sieve
sort";
  version = "1.1.0
0.11
0.4
0.10";
  src = ././vendor/quickcheck-1.1.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "quickcheck
quickcheck
btree_set_range
out_of_bounds
reverse
reverse_single
sieve
sort";
  #   license = lib.licenses.mit;
  # };
}
