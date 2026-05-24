{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "ipnet
ipnet";
  version = "2.12.0
0
0.8
1
1
1";
  src = ././vendor/ipnet-2.12.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "ipnet
ipnet";
  #   license = lib.licenses.mit;
  # };
}
