{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "phf_generator
phf_generator
gen_hash_test
benches";
  version = "0.11.3
0.3.6
^0.11.2
0.8
0.3.6";
  src = ././vendor/phf_generator-0.11.3;
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
