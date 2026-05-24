{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "lattice-slh-dsa
slh_dsa
keygen
serialize
sign_verify
coverage
integration
kat
kat_vectors
safe_api
slh_dsa_bench";
  version = "0.3.3
0.2
1
0.10
0.10
2
1
0.5
1
0.10";
  src = ././vendor/lattice-slh-dsa-0.3.3;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "lattice-slh-dsa
slh_dsa
keygen
serialize
sign_verify
coverage
integration
kat
kat_vectors
safe_api
slh_dsa_bench";
  #   license = lib.licenses.mit;
  # };
}
