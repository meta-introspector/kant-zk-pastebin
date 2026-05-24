{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "rustix
rustix
mod";
  version = "1.1.4
2.4.0
1.0.0
1.0.0
1.0
0.2.171
0.3.10
0.9.0
2.0.0
1.1.0
3.5.0
0.12
0.4
0.2.182
0.3.10
0.12
0.2.182
0.3.10
0.3.10
>=0.52, <0.62
1.20.3";
  src = ././vendor/rustix-1.1.4;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "rustix
rustix
mod";
  #   license = lib.licenses.mit;
  # };
}
