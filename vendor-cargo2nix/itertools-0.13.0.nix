{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "itertools
tuple_combinations
tuples
fold_specialization
combinations_with_replacement
tree_reduce
bench1
combinations
powerset
specializations";
  version = "0.13.0
1.0
0.4.0
1.0.0
0.2
0.9
0.7";
  src = ././vendor/itertools-0.13.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "itertools
tuple_combinations
tuples
fold_specialization
combinations_with_replacement
tree_reduce
bench1
combinations
powerset
specializations";
  #   license = lib.licenses.mit;
  # };
}
