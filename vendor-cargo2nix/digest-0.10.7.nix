{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "digest";
  version = "0.10.7
0.3
0.10
0.9
0.1.3
2.4";
  src = ././vendor/digest-0.10.7;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "digest";
  #   license = lib.licenses.mit;
  # };
}
