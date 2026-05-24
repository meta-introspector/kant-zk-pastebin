{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "dilithium-rs
dilithium
keygen
serialize
sign_verify
coverage
kat_vectors
multi_vector_kat
round_trip
dilithium_bench";
  version = "0.2.0
0.2
1
0.10
0.10
2
1
0.5
0.8
0.10";
  src = ././vendor/dilithium-rs-0.2.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "dilithium-rs
dilithium
keygen
serialize
sign_verify
coverage
kat_vectors
multi_vector_kat
round_trip
dilithium_bench";
  #   license = lib.licenses.mit;
  # };
}
