{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "blake2b_simd
blake2b_simd";
  version = "1.0.4
0.3.5
0.7.0
0.4.2";
  src = ././vendor/blake2b_simd-1.0.4;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "blake2b_simd
blake2b_simd";
  #   license = lib.licenses.mit;
  # };
}
