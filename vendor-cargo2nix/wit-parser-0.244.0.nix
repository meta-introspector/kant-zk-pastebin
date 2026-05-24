{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "wit-parser
wit_parser
all";
  version = "0.244.0
1.0.58
2
2.7.0
0.4.17
1.0.0
1.0.166
1.0.166
1
0.2.2
0.244.0
1.244.0
0.11
0.8.1
1.3.0
1";
  src = ././vendor/wit-parser-0.244.0;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "wit-parser
wit_parser
all";
  #   license = lib.licenses.mit;
  # };
}
