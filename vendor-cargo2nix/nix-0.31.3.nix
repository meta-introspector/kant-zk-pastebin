{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "nix
nix
test
test-aio-drop
test-clearenv
test-prctl";
  version = "0.31.3
2.3.3
1.0
0.2.186
0.9
0.1.0
0.1
0.12
0.9
1.0.7
3.7.1
0.2.1
0.5.3
0.4";
  src = ././vendor/nix-0.31.3;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "nix
nix
test
test-aio-drop
test-clearenv
test-prctl";
  #   license = lib.licenses.mit;
  # };
}
