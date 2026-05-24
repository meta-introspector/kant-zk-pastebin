{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "falcon-rs
falcon
falcon-rs
expand_key
keygen
serialize
sign_verify
bench_falcon
fips206_kat
full_coverage
gen_fips206_vectors
kat_test
nist_kat
prop_tests
timing_test
falcon_bench";
  version = "0.2.4
0.2
0.2
1
1
0.5
1";
  src = ././vendor/falcon-rs-0.2.4;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "falcon-rs
falcon
falcon-rs
expand_key
keygen
serialize
sign_verify
bench_falcon
fips206_kat
full_coverage
gen_fips206_vectors
kat_test
nist_kat
prop_tests
timing_test
falcon_bench";
  #   license = lib.licenses.mit;
  # };
}
