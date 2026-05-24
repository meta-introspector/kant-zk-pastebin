{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "crossbeam-utils
crossbeam_utils
atomic_cell
cache_padded
parker
sharded_lock
thread
wait_group
atomic_cell";
  version = "0.8.21
0.8
0.7.1";
  src = ././vendor/crossbeam-utils-0.8.21;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "crossbeam-utils
crossbeam_utils
atomic_cell
cache_padded
parker
sharded_lock
thread
wait_group
atomic_cell";
  #   license = lib.licenses.mit;
  # };
}
