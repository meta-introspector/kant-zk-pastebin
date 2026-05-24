{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "bytes
bytes
test_buf
test_buf_mut
test_bytes
test_bytes_odd_alloc
test_bytes_vec_alloc
test_chain
test_debug
test_iter
test_limit
test_reader
test_serde
test_take
buf
bytes
bytes_mut";
  version = "1.11.1
1.3
1.0.60
1.0
0.7";
  src = ././vendor/bytes-1.11.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "bytes
bytes
test_buf
test_buf_mut
test_bytes
test_bytes_odd_alloc
test_bytes_vec_alloc
test_chain
test_debug
test_iter
test_limit
test_reader
test_serde
test_take
buf
bytes
bytes_mut";
  #   license = lib.licenses.mit;
  # };
}
