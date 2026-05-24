{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "http";
  version = "0.2.12
1
1.0.5
1
0.3
<=1.8
0.9.0
0.7.0
3.0.5
1.0
1.0";
  src = ././vendor/http-0.2.12;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "http";
  #   license = lib.licenses.mit;
  # };
}
