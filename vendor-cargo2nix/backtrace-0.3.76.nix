{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "backtrace
backtrace
backtrace
raw
accuracy
concurrent-panics
current-exe-mismatch
long_fn_name
sgx-image-base
skip_inner_frames
smoke
benchmarks";
  version = "0.3.76
1.0
0.5.0
0.1.24
1.0
0.8
0.2
0.25.0
0.2.156
0.8
0.37.0
0.8.1";
  src = ././vendor/backtrace-0.3.76;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "backtrace
backtrace
backtrace
raw
accuracy
concurrent-panics
current-exe-mismatch
long_fn_name
sgx-image-base
skip_inner_frames
smoke
benchmarks";
  #   license = lib.licenses.mit;
  # };
}
