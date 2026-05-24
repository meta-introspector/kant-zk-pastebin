{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "once_cell
once_cell
bench
bench_acquire
lazy_static
reentrant_init_deadlocks
regex
test_synchronization
it";
  version = "1.21.4
1.1.3
0.9.10
1.8
1.1.3
1.10.6";
  src = ././vendor/once_cell-1.21.4;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "once_cell
once_cell
bench
bench_acquire
lazy_static
reentrant_init_deadlocks
regex
test_synchronization
it";
  #   license = lib.licenses.mit;
  # };
}
