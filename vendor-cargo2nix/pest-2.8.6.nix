{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "pest
pest
parens
calculator
json
stack";
  version = "2.8.6
2.4.0
7.2.0
1.0.145
1.0.85
0.1.5
0.5.1
7.2.0";
  src = ././vendor/pest-2.8.6;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "pest
pest
parens
calculator
json
stack";
  #   license = lib.licenses.mit;
  # };
}
