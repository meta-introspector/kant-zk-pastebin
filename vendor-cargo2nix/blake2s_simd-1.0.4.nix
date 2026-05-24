{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "blake2s_simd
blake2s_simd";
  version = "1.0.4
0.3.5
0.7.0
0.4.2";
  src = ././vendor/blake2s_simd-1.0.4;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "blake2s_simd
blake2s_simd";
  #   license = lib.licenses.mit;
  # };
}
