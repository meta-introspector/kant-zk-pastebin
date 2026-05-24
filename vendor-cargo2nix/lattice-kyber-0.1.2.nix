{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "lattice-kyber
kyber
keygen_encaps
serialize
kat_vectors
kem_tests
kyber_bench";
  version = "0.1.2
0.2
1
0.10
2
1
0.5";
  src = ././vendor/lattice-kyber-0.1.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "lattice-kyber
kyber
keygen_encaps
serialize
kat_vectors
kem_tests
kyber_bench";
  #   license = lib.licenses.mit;
  # };
}
