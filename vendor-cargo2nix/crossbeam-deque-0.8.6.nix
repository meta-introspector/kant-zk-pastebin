{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "crossbeam-deque
crossbeam_deque
fifo
injector
lifo
steal";
  version = "0.8.6
0.9.17
0.8.18
0.8";
  src = ././vendor/crossbeam-deque-0.8.6;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "crossbeam-deque
crossbeam_deque
fifo
injector
lifo
steal";
  #   license = lib.licenses.mit;
  # };
}
