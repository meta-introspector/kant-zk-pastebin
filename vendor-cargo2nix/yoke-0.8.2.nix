{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "yoke
yoke
bincode
miri";
  version = "0.8.2
1.2.0
0.8.2
0.1.6
1.3.1
1.0.3
1.0.220";
  src = ././vendor/yoke-0.8.2;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "yoke
yoke
bincode
miri";
  #   license = lib.licenses.mit;
  # };
}
