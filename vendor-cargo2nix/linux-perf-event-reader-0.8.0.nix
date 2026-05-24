{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "linux-perf-event-reader";
  version = "0.8.0
1.3.2
1.4.3
2.4.1
1.0.30";
  src = ././vendor/linux-perf-event-reader-0.8.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "linux-perf-event-reader";
  #   license = lib.licenses.mit;
  # };
}
