{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "phf_generator
phf_generator
gen_hash_test
benches";
  version = "0.13.1
2.1.0
^0.13.1
0.6.0";
  src = ././vendor/phf_generator-0.13.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "phf_generator
phf_generator
gen_hash_test
benches";
  #   license = lib.licenses.mit;
  # };
}
