{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "simd-adler32
simd_adler32";
  version = "0.3.9
1.0.2
1.2.0
0.3
0.8";
  src = ././vendor/simd-adler32-0.3.9;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "simd-adler32
simd_adler32";
  #   license = lib.licenses.mit;
  # };
}
