{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "regex-automata
regex_automata
integration";
  version = "0.4.14
1.0.0
0.4.14
2.6.0
0.8.5
1.0.69
1.3.0
0.3.3
0.9.3
1.0.3
0.1.0";
  src = ././vendor/regex-automata-0.4.14;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "regex-automata
regex_automata
integration";
  #   license = lib.licenses.mit;
  # };
}
