{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "rayon-core
rayon_core
double_init_fail
init_zero_threads
scope_join
scoped_threadpool
simple_panic
stack_overflow_crash
use_current_thread";
  version = "1.13.0
0.8.1
0.8.0
0.1.0
0.9
0.4
1.0
0.2";
  src = ././vendor/rayon-core-1.13.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "rayon-core
rayon_core
double_init_fail
init_zero_threads
scope_join
scoped_threadpool
simple_panic
stack_overflow_crash
use_current_thread";
  #   license = lib.licenses.mit;
  # };
}
