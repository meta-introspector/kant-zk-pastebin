{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "hyper
hyper";
  version = "0.14.32
1
0.3
0.3
0.3
0.3.24
0.2
0.4
1.8
1.0
1
0.2
0.2.4
>=0.4.7, <0.6.0
1.27
0.3
0.1
0.3
0.3
0.1
1.0
0.4
1.0
1.0
0.3
1.27
0.4
0.7
0.4
2.2
0.27.2";
  src = ././vendor/hyper-0.14.32;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "hyper
hyper";
  #   license = lib.licenses.mit;
  # };
}
