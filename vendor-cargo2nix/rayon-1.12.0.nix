{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "rayon
rayon
chars
clones
collect
cross-pool
debug
drain_vec
intersperse
issue671
issue671-unzip
iter_panic
named-threads
octillion
par_bridge_recursion
producer_split_at
sort-panic-safe
str";
  version = "1.12.0
1
1.13.0
0.1.0
0.9
0.4";
  src = ././vendor/rayon-1.12.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "rayon
rayon
chars
clones
collect
cross-pool
debug
drain_vec
intersperse
issue671
issue671-unzip
iter_panic
named-threads
octillion
par_bridge_recursion
producer_split_at
sort-panic-safe
str";
  #   license = lib.licenses.mit;
  # };
}
