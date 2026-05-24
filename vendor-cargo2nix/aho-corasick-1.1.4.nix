{ mkRustCrate, fetchFromGitHub, lib }:

mkRustCrate {
  name = "aho-corasick
aho_corasick";
  version = "1.1.4
0.4.17
2.4.0
0.3.3";
  src = ././vendor/aho-corasick-1.1.4;
  buildInputs = [ ];
  dependencies = { };
  
  # Add any crate-specific configuration here
  # meta = {
  #   description = "aho-corasick
aho_corasick";
  #   license = lib.licenses.mit;
  # };
}
