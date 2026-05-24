{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "redox_syscall
syscall";
  version = "0.7.4
2.4
1.0.0
0.7";
  src = ././vendor/redox_syscall-0.7.4;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "redox_syscall
syscall";
  #   license = lib.licenses.mit;
  # };
}
