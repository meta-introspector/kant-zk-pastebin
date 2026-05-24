{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "half
convert";
  version = "1.8.3
1.4.1
0.2.14
1.0
0.6.0
0.3.5
1.0
1.0
0.8.4";
  src = ././vendor/half-1.8.3;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "half
convert";
  #   license = lib.licenses.mit;
  # };
}
