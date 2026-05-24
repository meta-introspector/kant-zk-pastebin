{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "libredox
libredox";
  version = "0.1.16
2
0.6
0.2
0.2
0.7";
  src = ././vendor/libredox-0.1.16;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "libredox
libredox";
  #   license = lib.licenses.mit;
  # };
}
