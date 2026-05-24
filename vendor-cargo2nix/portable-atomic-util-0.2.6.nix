{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "portable-atomic-util
portable_atomic_util
arc";
  version = "0.2.6
1.5.1
0.1";
  src = ././vendor/portable-atomic-util-0.2.6;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "portable-atomic-util
portable_atomic_util
arc";
  #   license = lib.licenses.mit;
  # };
}
