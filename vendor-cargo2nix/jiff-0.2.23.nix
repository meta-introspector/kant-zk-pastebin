{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "jiff
jiff
integration";
  version = "0.2.23
0.2
0.1.6
0.4.21
1.0.221
1.0.81
0.4.38
0.10.0
2.1.0
1.39.0
0.4.21
1.0.3
1.0.203
1.0.117
0.9.34
1.4.0
0.3.36
2.0.0
0.1.3
2.5.0
0.3.50
0.2.70
=0.2.23
0.1.3
3.9.0
1.10.0
0.2.4
>=0.52.0, <=0.61.*";
  src = ././vendor/jiff-0.2.23;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "jiff
jiff
integration";
  #   license = lib.licenses.mit;
  # };
}
