{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "tera
tera";
  version = "1.20.1
0.4.27
0.9
0.9.1
2.1
1.4
2.2
2.5.5
2.5.5
0.8
1.7
1.0
1.0
0.1
1.12
1
1.0
3";
  src = ././vendor/tera-1.20.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "tera
tera";
  #   license = lib.licenses.mit;
  # };
}
