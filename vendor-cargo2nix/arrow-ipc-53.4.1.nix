{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "arrow-ipc
arrow_ipc";
  version = "53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
53.4.1
24.3.25
0.11
0.13.0
3.3";
  src = ././vendor/arrow-ipc-53.4.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "arrow-ipc
arrow_ipc";
  #   license = lib.licenses.mit;
  # };
}
