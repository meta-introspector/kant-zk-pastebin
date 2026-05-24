{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "constant_time_eq
constant_time_eq
count_instructions
count_instructions_classic
count_instructions_generic
exhaustive
bench
bench_classic
bench_generic";
  version = "0.4.2
0.2.0
0.5.1";
  src = ././vendor/constant_time_eq-0.4.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "constant_time_eq
constant_time_eq
count_instructions
count_instructions_classic
count_instructions_generic
exhaustive
bench
bench_classic
bench_generic";
  #   license = lib.licenses.mit;
  # };
}
