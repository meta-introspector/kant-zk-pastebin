{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "libm
libm";
  version = "0.2.16
0.1.35";
  src = ././vendor/libm-0.2.16;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "libm
libm";
  #   license = lib.licenses.mit;
  # };
}
