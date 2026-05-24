{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "serde_json
serde_json
compiletest
debug
lexical
map
regression
stream
test";
  version = "1.0.149
2.2.3
1.0
2
1.0.220
1.0
1.0.11
2.0.2
1.0.18
1.0.13
1.0.194
0.11.10
1.0.166
0.1.8
1.0.108
1.0.220";
  src = ././vendor/serde_json-1.0.149;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "serde_json
serde_json
compiletest
debug
lexical
map
regression
stream
test";
  #   license = lib.licenses.mit;
  # };
}
