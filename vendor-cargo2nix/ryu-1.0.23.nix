{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "ryu
ryu
upstream_benchmark
common_test
d2s_intrinsics_test
d2s_table_test
d2s_test
exhaustive
f2s_test
s2d_test
s2f_test
bench";
  version = "1.0.23
0.1
1.8
0.10
0.10
0.5
0.8";
  src = ././vendor/ryu-1.0.23;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "ryu
ryu
upstream_benchmark
common_test
d2s_intrinsics_test
d2s_table_test
d2s_test
exhaustive
f2s_test
s2d_test
s2f_test
bench";
  #   license = lib.licenses.mit;
  # };
}
