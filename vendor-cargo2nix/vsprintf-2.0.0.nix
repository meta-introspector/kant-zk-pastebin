{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "vsprintf";
  version = "2.0.0
0.2
1.0";
  src = ././vendor/vsprintf-2.0.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "vsprintf";
  #   license = lib.licenses.mit;
  # };
}
