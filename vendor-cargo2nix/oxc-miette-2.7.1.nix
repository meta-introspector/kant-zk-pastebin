{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "oxc-miette
miette";
  version = "2.7.1
0.3.74
0.2.1
1
4
=2.7.1
1
3.0.2
3.1.0
3.0.0
0.4.2
0.16.2
2
1.12.0
0.2.0
0.3
0.3.3
1.46.1
1.5
1.11
1.0
1.0.26
1.0.140
1.0.104";
  src = ././vendor/oxc-miette-2.7.1;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "oxc-miette
miette";
  #   license = lib.licenses.mit;
  # };
}
