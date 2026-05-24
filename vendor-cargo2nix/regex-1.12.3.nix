{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "regex
regex
integration";
  version = "1.12.3
1.0.0
2.6.0
0.4.12
0.8.5
1.0.69
0.3
0.9.3
1.0.3
0.1.0";
  src = ././vendor/regex-1.12.3;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "regex
regex
integration";
  #   license = lib.licenses.mit;
  # };
}
