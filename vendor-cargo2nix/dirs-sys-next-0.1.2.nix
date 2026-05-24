{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "dirs-sys-next";
  version = "0.1.2
0.4.0
0.2
0.3";
  src = ././vendor/dirs-sys-next-0.1.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "dirs-sys-next";
  #   license = lib.licenses.mit;
  # };
}
