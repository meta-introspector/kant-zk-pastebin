{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "serde_yaml";
  version = "0.9.34+deprecated
2.2.1
1.0
1.0
1.0.195
0.2.11
1.0.79
2.0
1.0.195";
  src = ././vendor/serde_yaml-0.9.34+deprecated;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "serde_yaml";
  #   license = lib.licenses.mit;
  # };
}
