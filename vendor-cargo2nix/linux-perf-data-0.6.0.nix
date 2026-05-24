{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "linux-perf-data";
  version = "0.6.0
1.4.3
1.2.0
0.8.0
2.4.1
1.0.30";
  src = ././vendor/linux-perf-data-0.6.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "linux-perf-data";
  #   license = lib.licenses.mit;
  # };
}
