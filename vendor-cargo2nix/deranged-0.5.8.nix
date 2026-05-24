{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "deranged
deranged";
  version = "0.5.8
=0.3.0
0.2.15
0.2.0
1.0.3
0.10.0
0.8.4
0.9.0
1.0.220
0.10.0
0.8.4
0.9.0
1.0.86";
  src = ././vendor/deranged-0.5.8;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "deranged
deranged";
  #   license = lib.licenses.mit;
  # };
}
