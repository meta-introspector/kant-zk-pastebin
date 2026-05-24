{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "lattice-safe-suite
lattice_safe_suite
pqc_bench";
  version = "0.4.3
0.2
0.2
0.2
0.1.2
0.3.3
0.5";
  src = ././vendor/lattice-safe-suite-0.4.3;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "lattice-safe-suite
lattice_safe_suite
pqc_bench";
  #   license = lib.licenses.mit;
  # };
}
