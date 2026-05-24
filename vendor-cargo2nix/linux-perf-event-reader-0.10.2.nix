{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "linux-perf-event-reader
linux_perf_event_reader";
  version = "0.10.2
2
1.4.3
2.4.1
2";
  src = ././vendor/linux-perf-event-reader-0.10.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "linux-perf-event-reader
linux_perf_event_reader";
  #   license = lib.licenses.mit;
  # };
}
