{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "twox-hash";
  version = "1.6.3
>= 0.1, < 2
0.8
0.10
0.9
>= 0.3.10, < 0.9
1.0
1.0
1.0";
  src = ././vendor/twox-hash-1.6.3;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "twox-hash";
  #   license = lib.licenses.mit;
  # };
}
