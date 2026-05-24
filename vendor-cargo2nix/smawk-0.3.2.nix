{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "smawk";
  version = "0.3.2
0.15.4
0.2.14
0.8.4
0.3.1
0.9.4";
  src = ././vendor/smawk-0.3.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "smawk";
  #   license = lib.licenses.mit;
  # };
}
