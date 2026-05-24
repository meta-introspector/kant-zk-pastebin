{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "anes
bench_main";
  version = "0.1.6
1.2
0.3
0.2.66";
  src = ././vendor/anes-0.1.6;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "anes
bench_main";
  #   license = lib.licenses.mit;
  # };
}
